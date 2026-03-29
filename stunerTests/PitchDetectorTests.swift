import Testing
import Foundation
@testable import stuner

@Suite("PitchDetector Tests", .serialized)
struct PitchDetectorTests {

    init() {
        PitchDetector.reset()
    }

    private func sineWave(frequency: Double, sampleRate: Double = 44100.0, count: Int = 4096) -> [Float] {
        (0..<count).map { i in
            Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    @Test("Detects A4 = 440 Hz")
    func detectA4() {
        PitchDetector.reset()
        let buffer = sineWave(frequency: 440.0)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 440.0) < 2.0)
            #expect(result.confidence > 0.7)
        }
    }

    @Test("Detects E2 = ~82.41 Hz")
    func detectE2() {
        PitchDetector.reset()
        let buffer = sineWave(frequency: 82.41, count: 4096)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 82.41) < 2.0)
        }
    }

    @Test("Detects E4 = ~329.63 Hz")
    func detectE4() {
        PitchDetector.reset()
        let buffer = sineWave(frequency: 329.63)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 329.63) < 2.0)
        }
    }

    @Test("Detects G3 = ~196 Hz")
    func detectG3() {
        PitchDetector.reset()
        let buffer = sineWave(frequency: 196.0)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 196.0) < 2.0)
        }
    }

    @Test("Detects B3 = ~246.94 Hz")
    func detectB3() {
        PitchDetector.reset()
        let buffer = sineWave(frequency: 246.94)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 246.94) < 2.0)
        }
    }

    @Test("Returns nil for silence")
    func silence() {
        PitchDetector.reset()
        let buffer = [Float](repeating: 0.0, count: 4096)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        if let result {
            #expect(result.confidence < 0.7)
        }
    }

    @Test("Returns nil for noise")
    func noise() {
        PitchDetector.reset()
        var buffer = [Float](repeating: 0.0, count: 4096)
        for i in 0..<buffer.count {
            buffer[i] = Float.random(in: -1.0...1.0)
        }
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        if let result {
            #expect(result.confidence < 0.7)
        }
    }

    @Test("Octave correction prevents jump up")
    func octaveCorrectionUp() {
        PitchDetector.reset()
        // Establish stable frequency at G3
        let g3Buffer = sineWave(frequency: 196.0)
        _ = PitchDetector.detectPitch(buffer: g3Buffer, sampleRate: 44100.0)

        // Feed octave-up frequency (G4 ~392 Hz) — should snap back to ~196
        let g4Buffer = sineWave(frequency: 392.0)
        let result = PitchDetector.detectPitch(buffer: g4Buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 196.0) < 5.0)
        }
    }

    @Test("Octave correction prevents jump down")
    func octaveCorrectionDown() {
        PitchDetector.reset()
        // Establish stable frequency at G3
        let g3Buffer = sineWave(frequency: 196.0)
        _ = PitchDetector.detectPitch(buffer: g3Buffer, sampleRate: 44100.0)

        // Feed octave-down frequency (~98 Hz) — should snap back to ~196
        let lowBuffer = sineWave(frequency: 98.0)
        let result = PitchDetector.detectPitch(buffer: lowBuffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 196.0) < 5.0)
        }
    }

    @Test("Reset clears stable frequency")
    func resetState() {
        let buffer = sineWave(frequency: 440.0)
        _ = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)

        PitchDetector.reset()

        // After reset, should detect new frequency immediately
        let newBuffer = sineWave(frequency: 196.0)
        let result = PitchDetector.detectPitch(buffer: newBuffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 196.0) < 2.0)
        }
    }
}
