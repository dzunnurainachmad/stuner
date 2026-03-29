import Foundation
import Testing
@testable import stuner

@Suite("TunerState Tests", .serialized)
struct TunerStateTests {

    init() {
        // Reset UserDefaults before each test to prevent state leaking between tests
        UserDefaults.standard.removeObject(forKey: "a4Frequency")
        UserDefaults.standard.removeObject(forKey: "selectedTuningId")
        UserDefaults.standard.removeObject(forKey: "customTunings")
    }

    @Test("Default state")
    func defaultState() {
        let state = TunerState()
        #expect(state.a4Frequency == 440.0)
        #expect(state.selectedTuning.name == "Standard")
        #expect(state.selectedString == nil) // auto-detect
        #expect(state.detectedFrequency == nil)
        #expect(state.centsOffset == 0)
        #expect(state.isActive == false)
    }

    @Test("Process pitch updates state - E4 exact")
    func processPitchExact() {
        let state = TunerState()
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.detectedFrequency == e4Freq)
        #expect(state.detectedNote == .E)
        #expect(abs(state.centsOffset) < 1.0)
        #expect(state.confidence == 0.9)
    }

    @Test("Process pitch - low confidence ignored")
    func lowConfidence() {
        let state = TunerState()
        state.processPitch(frequency: 440.0, confidence: 0.3)
        #expect(state.detectedFrequency == nil)
    }

    @Test("Auto-detect finds closest string")
    func autoDetect() {
        let state = TunerState()
        // 82.41 Hz = E2, string 6 in standard tuning
        state.processPitch(frequency: 82.41, confidence: 0.9)
        #expect(state.targetString?.stringNumber == 6)
    }

    @Test("Locked string overrides auto-detect")
    func lockedString() {
        let state = TunerState()
        state.selectedString = 1  // Lock to string 1 (E4)
        // Play a frequency close to E2 — should still target string 1
        state.processPitch(frequency: 82.41, confidence: 0.9)
        #expect(state.targetString?.stringNumber == 1)
    }

    @Test("Cents offset calculation")
    func centsOffset() {
        let state = TunerState()
        // E4 ≈ 329.63 Hz, play slightly sharp → should be positive cents
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq * 1.005, confidence: 0.9)
        #expect(state.centsOffset > 0)
        #expect(state.centsOffset < 50)
    }

    @Test("Custom A4 affects detection")
    func customA4() {
        let state = TunerState()
        state.a4Frequency = 432.0
        // E4 frequency with a4=432 should be exactly in tune
        let e4Freq = Note.E.frequency(octave: 4, a4: 432.0)
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.detectedNote == .E)
        #expect(abs(state.centsOffset) < 1.0)

        // Clean up
        state.a4Frequency = 440.0
    }

    @Test("Saved tunings persist via UserDefaults")
    func savedTunings() {
        let state = TunerState()
        let custom = GuitarTuning(
            name: "Test Tuning",
            strings: GuitarTuning.standard.strings,
            isBuiltIn: false
        )
        state.addCustomTuning(custom)
        #expect(state.customTunings.count >= 1)
        #expect(state.customTunings.contains { $0.name == "Test Tuning" })

        // Clean up
        state.removeCustomTuning(id: custom.id)
    }
}
