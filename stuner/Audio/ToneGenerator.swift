import AVFoundation
import Foundation

final class ToneGenerator {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isPlaying = false
    private var currentFrequency: Double = 0

    init() {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func play(frequency: Double) {
        stop()
        currentFrequency = frequency

        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // Generate 1 second of sine wave, schedule it in a loop
        let frameCount = AVAudioFrameCount(sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            data[i] = Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate)) * 0.3
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            engine.prepare()
            try engine.start()
            playerNode.play()
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            isPlaying = true
        } catch {
            // Silently fail — tone is a convenience feature
        }
    }

    func stop() {
        guard isPlaying else { return }
        playerNode.stop()
        engine.stop()
        isPlaying = false
    }
}
