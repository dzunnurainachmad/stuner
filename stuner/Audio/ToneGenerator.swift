import AVFoundation
import Foundation

final class ToneGenerator {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var isPlaying = false
    private let sampleRate: Double = 44100

    private var phase: Double = 0
    private var currentFrequency: Double = 0
    private var targetFrequency: Double = 0
    private var amplitude: Double = 0
    private var targetAmplitude: Double = 0.8

    func play(frequency: Double) {
        targetFrequency = frequency

        if isPlaying {
            // Already playing — frequency will smoothly transition via render callback
            return
        }

        currentFrequency = frequency
        phase = 0
        amplitude = 0  // Start silent, fade in
        targetAmplitude = 0.5

        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let node = AVAudioSourceNode { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
            let buf = ablPointer[0]
            let data = buf.mData!.assumingMemoryBound(to: Float.self)

            for i in 0..<Int(frameCount) {
                // Smooth frequency transition
                currentFrequency += (targetFrequency - currentFrequency) * 0.001
                // Boost low frequencies — speakers are quieter at low freq
                let freqBoost = min(2.0, max(1.0, 300.0 / currentFrequency))
                let adjustedAmplitude = min(1.0, targetAmplitude * freqBoost)
                // Smooth amplitude (fade in/out)
                amplitude += (adjustedAmplitude - amplitude) * 0.005

                // Add harmonics for low frequencies so phone speakers can reproduce them
                let fundamental = sin(phase)
                let harmonic2 = sin(phase * 2.0) * 0.5  // octave up
                let harmonic3 = sin(phase * 3.0) * 0.3  // octave + fifth
                // Blend: more harmonics for low notes, pure sine for high notes
                let harmonicMix = min(1.0, max(0.0, (250.0 - currentFrequency) / 170.0))
                let sample = fundamental * (1.0 - harmonicMix * 0.4)
                    + harmonic2 * harmonicMix
                    + harmonic3 * harmonicMix
                data[i] = Float(sample * amplitude)
                phase += 2.0 * .pi * currentFrequency / sampleRate
                if phase > 2.0 * .pi { phase -= 2.0 * .pi }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            engine.prepare()
            try engine.start()
            self.engine = engine
            self.sourceNode = node
            isPlaying = true
        } catch {
            print("ToneGenerator failed: \(error)")
        }
    }

    func stop() {
        guard isPlaying else { return }
        // Fade out then stop
        targetAmplitude = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            engine?.stop()
            if let node = sourceNode {
                engine?.detach(node)
            }
            engine = nil
            sourceNode = nil
            isPlaying = false
        }
    }
}
