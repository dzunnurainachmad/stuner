import AVFoundation
import Accelerate
import Foundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 4096
    private nonisolated(unsafe) var onPitch: (@Sendable (PitchResult) -> Void)?

    var sampleRate: Double {
        engine.inputNode.outputFormat(forBus: 0).sampleRate
    }

    func start(onPitch: @escaping @Sendable (PitchResult) -> Void) {
        self.onPitch = onPitch

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else {
                print("Microphone permission denied")
                return
            }
            DispatchQueue.main.async {
                self?.startEngine()
            }
        }
    }

    private func startEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            print("Audio format: \(format)")
            print("Sample rate: \(format.sampleRate), channels: \(format.channelCount)")

            guard format.channelCount > 0, format.sampleRate > 0 else {
                print("Invalid audio format - no input available")
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            engine.prepare()
            try engine.start()
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        let rate = buffer.format.sampleRate

        // Noise gate: calculate RMS level, ignore if too quiet
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))
        guard rms > 0.005 else { return }

        if let result = PitchDetector.detectPitch(buffer: samples, sampleRate: rate) {
            onPitch?(result)
        }
    }
}
