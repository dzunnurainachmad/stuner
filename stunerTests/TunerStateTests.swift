import Foundation
import Testing
@testable import stuner

@Suite("TunerState Tests", .serialized)
struct TunerStateTests {

    init() {
        UserDefaults.standard.removeObject(forKey: "a4Frequency")
        UserDefaults.standard.removeObject(forKey: "selectedTuningId")
        UserDefaults.standard.removeObject(forKey: "customTunings")
    }

    @Test("Default state")
    func defaultState() {
        let state = TunerState()
        #expect(state.a4Frequency == 440.0)
        #expect(state.selectedTuning.name == "Standard")
        #expect(state.selectedString == nil)
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
        state.processPitch(frequency: 329.63, confidence: 0.5)
        #expect(state.detectedFrequency == nil)
    }

    @Test("Process pitch - confidence at threshold passes")
    func confidenceThreshold() {
        let state = TunerState()
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq, confidence: 0.8)
        #expect(state.detectedFrequency == e4Freq)
    }

    @Test("Auto-detect finds closest string")
    func autoDetect() {
        let state = TunerState()
        state.processPitch(frequency: 82.41, confidence: 0.9)
        #expect(state.targetString?.stringNumber == 6)
    }

    @Test("Locked string overrides auto-detect")
    func lockedString() {
        let state = TunerState()
        state.selectedString = 1
        state.processPitch(frequency: 82.41, confidence: 0.9)
        #expect(state.targetString?.stringNumber == 1)
    }

    @Test("Cents offset positive when sharp")
    func centsOffsetSharp() {
        let state = TunerState()
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq * 1.005, confidence: 0.9)
        #expect(state.centsOffset > 0)
        #expect(state.centsOffset < 50)
    }

    @Test("Cents offset negative when flat")
    func centsOffsetFlat() {
        let state = TunerState()
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq * 0.995, confidence: 0.9)
        #expect(state.centsOffset < 0)
        #expect(state.centsOffset > -50)
    }

    @Test("Cents offset clamped to ±50")
    func centsOffsetClamped() {
        let state = TunerState()
        state.selectedString = 1  // Lock to E4
        // Play a frequency far from E4
        state.processPitch(frequency: 500.0, confidence: 0.9)
        #expect(state.centsOffset == 50 || state.centsOffset == -50)
    }

    @Test("Custom A4 affects detection")
    func customA4() {
        let state = TunerState()
        state.a4Frequency = 432.0
        let e4Freq = Note.E.frequency(octave: 4, a4: 432.0)
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.detectedNote == .E)
        #expect(abs(state.centsOffset) < 1.0)
        state.a4Frequency = 440.0
    }

    @Test("String switch requires debounce")
    func stringSwitchDebounce() {
        let state = TunerState()
        // First detect E4 (string 1)
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.targetString?.stringNumber == 1)

        // Single reading near A2 should NOT switch (debounce)
        state.processPitch(frequency: 110.0, confidence: 0.9)
        #expect(state.targetString?.stringNumber == 1)
    }

    @Test("Clear detection resets state")
    func clearDetection() {
        let state = TunerState()
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.detectedFrequency != nil)

        state.clearDetection()
        #expect(state.detectedFrequency == nil)
        #expect(state.detectedNote == nil)
        #expect(state.centsOffset == 0)
        #expect(state.targetString == nil)
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
        state.removeCustomTuning(id: custom.id)
    }

    @Test("Select tuning resets selected string")
    func selectTuningResetsString() {
        let state = TunerState()
        state.selectedString = 3
        state.selectTuning(GuitarTuning.dropD)
        #expect(state.selectedString == nil)
        #expect(state.selectedTuning.name == "Drop D")
    }

    @Test("Pitch detection paused while tone is playing")
    func tonePlayingPausesPitchDetection() {
        let state = TunerState()
        state.isPlayingTone = true
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.detectedFrequency == nil)
    }

    @Test("Pitch detection resumes after tone stops")
    func toneStoppedResumesPitchDetection() {
        let state = TunerState()
        state.isPlayingTone = true
        let e4Freq = Note.E.frequency(octave: 4, a4: 440.0)
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.detectedFrequency == nil)

        state.isPlayingTone = false
        state.processPitch(frequency: e4Freq, confidence: 0.9)
        #expect(state.detectedFrequency == e4Freq)
    }
}
