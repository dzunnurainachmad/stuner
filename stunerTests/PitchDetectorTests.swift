import Testing
import Foundation
@testable import stuner

@Suite("PitchDetector Tests")
struct PitchDetectorTests {

    /// Generate a sine wave buffer at a given frequency
    private func sineWave(frequency: Double, sampleRate: Double = 44100.0, count: Int = 4096) -> [Float] {
        (0..<count).map { i in
            Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    @Test("Detects A4 = 440 Hz")
    func detectA4() {
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
        let buffer = sineWave(frequency: 82.41, count: 4096)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 82.41) < 2.0)
        }
    }

    @Test("Detects E4 = ~329.63 Hz")
    func detectE4() {
        let buffer = sineWave(frequency: 329.63)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        #expect(result != nil)
        if let result {
            #expect(abs(result.frequency - 329.63) < 2.0)
        }
    }

    @Test("Returns nil for silence")
    func silence() {
        let buffer = [Float](repeating: 0.0, count: 4096)
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        // Should return nil or very low confidence
        if let result {
            #expect(result.confidence < 0.7)
        }
    }

    @Test("Returns nil for noise")
    func noise() {
        var buffer = [Float](repeating: 0.0, count: 4096)
        for i in 0..<buffer.count {
            buffer[i] = Float.random(in: -1.0...1.0)
        }
        let result = PitchDetector.detectPitch(buffer: buffer, sampleRate: 44100.0)
        if let result {
            #expect(result.confidence < 0.7)
        }
    }
}
