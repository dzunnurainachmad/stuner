# stuner Guitar Tuner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a minimal iOS guitar tuner app with real-time pitch detection (YIN algorithm), reference tone playback, preset/custom tunings, and configurable A4 reference frequency.

**Architecture:** Unidirectional data flow — AVAudioEngine captures mic input → PitchDetector (YIN) extracts frequency → TunerState computes cents offset and closest string → SwiftUI views render state. ToneGenerator uses a separate AVAudioEngine output path for reference tones. All state is centralized in an `@Observable` TunerState class.

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, Accelerate (vDSP), iOS 18.0+, @Observable macro

**Status:** All tasks completed. App is fully functional with unit tests (Swift Testing) and UI tests (XCTest). Post-launch improvements: sub-octave correction in YIN (fixes E4/B3 octave-down jumps), landscape layout support, tone-playing pauses pitch detection, reduced debounce threshold (8→4), faster stable frequency lock-in (3→2), stronger EMA smoothing (80/20).

**Project notes:**
- Xcode uses `PBXFileSystemSynchronizedRootGroup` — files added to `stuner/` are auto-discovered, no pbxproj edits needed
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is enabled — audio work must explicitly opt out with `nonisolated` or custom actors
- Unit test target `stunerTests` uses Swift Testing framework; UI test target `stunerUITests` uses XCTest
- Testing on real iPhone device only (no simulator)
- UI tests reset UserDefaults via launch arguments for deterministic state

---

## File Structure

```
stuner/
  stunerApp.swift              (modify — wire up TunerState as environment)
  ContentView.swift            (modify — replace with TunerView)
  Models/
    Note.swift                 (create — Note enum, frequency calculation)
    GuitarTuning.swift         (create — StringTuning, GuitarTuning, presets)
  Audio/
    PitchDetector.swift        (create — YIN algorithm)
    AudioEngine.swift          (create — mic capture, feeds PitchDetector)
    ToneGenerator.swift        (create — sine wave playback)
  ViewModels/
    TunerState.swift           (create — central @Observable state)
  Views/
    TunerView.swift            (create — main tuner screen)
    StringSelectorView.swift   (create — 6 string circles)
    CentsIndicatorView.swift   (create — horizontal bar with dot)
    TuningPickerView.swift     (create — tuning selection sheet)
    SettingsView.swift         (create — A4 freq + custom tuning creator)

stunerTests/
  NoteTests.swift              (create)
  GuitarTuningTests.swift      (create)
  PitchDetectorTests.swift     (create)
  TunerStateTests.swift        (create)
```

---

### Task 1: Note Model and Frequency Calculation

**Files:**
- Create: `stuner/Models/Note.swift`
- Create: `stunerTests/NoteTests.swift`

- [x] **Step 1: Write the failing tests**

Create `stunerTests/NoteTests.swift`:

```swift
import Testing
@testable import stuner

@Suite("Note Tests")
struct NoteTests {

    @Test("Note has 12 cases")
    func noteCount() {
        #expect(Note.allCases.count == 12)
    }

    @Test("A4 is 440 Hz at standard tuning")
    func a4Frequency() {
        let freq = Note.A.frequency(octave: 4, a4: 440.0)
        #expect(abs(freq - 440.0) < 0.01)
    }

    @Test("A3 is 220 Hz")
    func a3Frequency() {
        let freq = Note.A.frequency(octave: 3, a4: 440.0)
        #expect(abs(freq - 220.0) < 0.01)
    }

    @Test("E2 is ~82.41 Hz at A4=440")
    func e2Frequency() {
        let freq = Note.E.frequency(octave: 2, a4: 440.0)
        #expect(abs(freq - 82.41) < 0.01)
    }

    @Test("C4 is ~261.63 Hz (middle C)")
    func c4Frequency() {
        let freq = Note.C.frequency(octave: 4, a4: 440.0)
        #expect(abs(freq - 261.63) < 0.01)
    }

    @Test("Custom A4 = 432 Hz changes all frequencies")
    func customA4() {
        let freq = Note.A.frequency(octave: 4, a4: 432.0)
        #expect(abs(freq - 432.0) < 0.01)
    }

    @Test("Note display name")
    func displayName() {
        #expect(Note.C.displayName == "C")
        #expect(Note.Cs.displayName == "C#")
        #expect(Note.Eb.displayName == "Eb")
    }

    @Test("Nearest note from frequency - exact A4")
    func nearestNoteExact() {
        let (note, octave, cents) = Note.nearest(to: 440.0, a4: 440.0)
        #expect(note == .A)
        #expect(octave == 4)
        #expect(abs(cents) < 0.1)
    }

    @Test("Nearest note from frequency - slightly sharp")
    func nearestNoteSharp() {
        let (note, octave, cents) = Note.nearest(to: 445.0, a4: 440.0)
        #expect(note == .A)
        #expect(octave == 4)
        #expect(cents > 0) // sharp = positive
    }

    @Test("Nearest note from frequency - E2")
    func nearestNoteE2() {
        let (note, octave, _) = Note.nearest(to: 82.41, a4: 440.0)
        #expect(note == .E)
        #expect(octave == 2)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: Build failure — `Note` not defined

- [x] **Step 3: Implement Note model**

Create `stuner/Models/Note.swift`:

```swift
import Foundation

enum Note: Int, CaseIterable, Codable, Sendable {
    case C = 0, Cs, D, Eb, E, F, Fs, G, Ab, A, Bb, B

    var displayName: String {
        switch self {
        case .C: "C"
        case .Cs: "C#"
        case .D: "D"
        case .Eb: "Eb"
        case .E: "E"
        case .F: "F"
        case .Fs: "F#"
        case .G: "G"
        case .Ab: "Ab"
        case .A: "A"
        case .Bb: "Bb"
        case .B: "B"
        }
    }

    /// Semitone distance from A (used for frequency calculation)
    private var semitonesFromA: Int {
        // A = 0, Bb = 1, B = 2, C = -9, etc.
        (rawValue - Note.A.rawValue)
    }

    /// Calculate frequency for this note at a given octave
    /// Formula: freq = a4 * 2^((octave - 4) + semitonesFromA / 12)
    func frequency(octave: Int, a4: Double = 440.0) -> Double {
        let semitonesFromA4 = Double(semitonesFromA) + Double(octave - 4) * 12.0
        return a4 * pow(2.0, semitonesFromA4 / 12.0)
    }

    /// Find the nearest note to a given frequency
    /// Returns (note, octave, centsOffset) where positive cents = sharp
    static func nearest(to frequency: Double, a4: Double = 440.0) -> (note: Note, octave: Int, cents: Double) {
        // Number of semitones from A4
        let semitonesFromA4 = 12.0 * log2(frequency / a4)
        let roundedSemitones = Int(round(semitonesFromA4))
        let cents = (semitonesFromA4 - Double(roundedSemitones)) * 100.0

        // Convert semitones offset to note + octave
        // A4 is rawValue 9, octave 4
        let noteIndex = ((roundedSemitones % 12) + 12 + Note.A.rawValue) % 12
        let octaveOffset = (roundedSemitones + Note.A.rawValue >= 0)
            ? (roundedSemitones + Note.A.rawValue) / 12
            : (roundedSemitones + Note.A.rawValue - 11) / 12
        let octave = 4 + octaveOffset

        let note = Note(rawValue: noteIndex)!
        return (note, octave, cents)
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: All NoteTests pass

- [x] **Step 5: Commit**

```bash
git add stuner/Models/Note.swift stunerTests/NoteTests.swift
git commit -m "feat: add Note model with frequency calculation and nearest-note lookup"
```

---

### Task 2: GuitarTuning Model and Presets

**Files:**
- Create: `stuner/Models/GuitarTuning.swift`
- Create: `stunerTests/GuitarTuningTests.swift`

- [x] **Step 1: Write the failing tests**

Create `stunerTests/GuitarTuningTests.swift`:

```swift
import Testing
@testable import stuner

@Suite("GuitarTuning Tests")
struct GuitarTuningTests {

    @Test("StringTuning stores note and octave")
    func stringTuning() {
        let s = StringTuning(stringNumber: 6, note: .E, octave: 2)
        #expect(s.stringNumber == 6)
        #expect(s.note == .E)
        #expect(s.octave == 2)
    }

    @Test("StringTuning frequency uses Note.frequency")
    func stringTuningFrequency() {
        let s = StringTuning(stringNumber: 1, note: .E, octave: 4)
        let freq = s.frequency(a4: 440.0)
        let expected = Note.E.frequency(octave: 4, a4: 440.0)
        #expect(abs(freq - expected) < 0.01)
    }

    @Test("StringTuning display shows note and octave")
    func stringTuningDisplay() {
        let s = StringTuning(stringNumber: 6, note: .E, octave: 2)
        #expect(s.displayName == "E2")
    }

    @Test("Standard tuning has correct strings")
    func standardTuning() {
        let std = GuitarTuning.standard
        #expect(std.name == "Standard")
        #expect(std.strings.count == 6)
        #expect(std.isBuiltIn == true)
        // String 6 (lowest) = E2
        #expect(std.strings[0].note == .E)
        #expect(std.strings[0].octave == 2)
        #expect(std.strings[0].stringNumber == 6)
        // String 1 (highest) = E4
        #expect(std.strings[5].note == .E)
        #expect(std.strings[5].octave == 4)
        #expect(std.strings[5].stringNumber == 1)
    }

    @Test("All 6 built-in tunings exist")
    func builtInTunings() {
        let all = GuitarTuning.builtIns
        #expect(all.count == 6)
        let names = all.map(\.name)
        #expect(names.contains("Standard"))
        #expect(names.contains("Drop D"))
        #expect(names.contains("Open G"))
        #expect(names.contains("Open D"))
        #expect(names.contains("DADGAD"))
        #expect(names.contains("Half Step Down"))
    }

    @Test("Drop D has D2 on string 6")
    func dropD() {
        let dropD = GuitarTuning.builtIns.first { $0.name == "Drop D" }!
        #expect(dropD.strings[0].note == .D)
        #expect(dropD.strings[0].octave == 2)
    }

    @Test("GuitarTuning is Codable")
    func codable() throws {
        let tuning = GuitarTuning.standard
        let data = try JSONEncoder().encode(tuning)
        let decoded = try JSONDecoder().decode(GuitarTuning.self, from: data)
        #expect(decoded.name == tuning.name)
        #expect(decoded.strings.count == 6)
    }

    @Test("closestString finds nearest string by frequency")
    func closestString() {
        let std = GuitarTuning.standard
        // 82 Hz is close to E2 (82.41 Hz) — string 6
        let match = std.closestString(to: 82.0, a4: 440.0)
        #expect(match.stringNumber == 6)
        #expect(match.note == .E)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: Build failure — `StringTuning`, `GuitarTuning` not defined

- [x] **Step 3: Implement GuitarTuning model**

Create `stuner/Models/GuitarTuning.swift`:

```swift
import Foundation

struct StringTuning: Codable, Sendable, Identifiable {
    var id: Int { stringNumber }
    let stringNumber: Int  // 1 = highest (thinnest), 6 = lowest (thickest)
    let note: Note
    let octave: Int

    var displayName: String {
        "\(note.displayName)\(octave)"
    }

    func frequency(a4: Double = 440.0) -> Double {
        note.frequency(octave: octave, a4: a4)
    }
}

struct GuitarTuning: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let strings: [StringTuning]  // ordered: string 6 (low) at index 0, string 1 (high) at index 5
    let isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, strings: [StringTuning], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.strings = strings
        self.isBuiltIn = isBuiltIn
    }

    /// Find the string whose target frequency is closest to the detected frequency
    func closestString(to frequency: Double, a4: Double = 440.0) -> StringTuning {
        strings.min(by: {
            abs(log2($0.frequency(a4: a4) / frequency)) < abs(log2($1.frequency(a4: a4) / frequency))
        })!
    }
}

// MARK: - Built-in tunings

extension GuitarTuning {
    /// Helper to build a 6-string tuning from (note, octave) pairs, ordered low to high
    private static func make(
        name: String,
        _ s6: (Note, Int), _ s5: (Note, Int), _ s4: (Note, Int),
        _ s3: (Note, Int), _ s2: (Note, Int), _ s1: (Note, Int)
    ) -> GuitarTuning {
        GuitarTuning(name: name, strings: [
            StringTuning(stringNumber: 6, note: s6.0, octave: s6.1),
            StringTuning(stringNumber: 5, note: s5.0, octave: s5.1),
            StringTuning(stringNumber: 4, note: s4.0, octave: s4.1),
            StringTuning(stringNumber: 3, note: s3.0, octave: s3.1),
            StringTuning(stringNumber: 2, note: s2.0, octave: s2.1),
            StringTuning(stringNumber: 1, note: s1.0, octave: s1.1),
        ], isBuiltIn: true)
    }

    static let standard = make(name: "Standard",
        (.E, 2), (.A, 2), (.D, 3), (.G, 3), (.B, 3), (.E, 4))

    static let dropD = make(name: "Drop D",
        (.D, 2), (.A, 2), (.D, 3), (.G, 3), (.B, 3), (.E, 4))

    static let openG = make(name: "Open G",
        (.D, 2), (.G, 2), (.D, 3), (.G, 3), (.B, 3), (.D, 4))

    static let openD = make(name: "Open D",
        (.D, 2), (.A, 2), (.D, 3), (.Fs, 3), (.A, 3), (.D, 4))

    static let dadgad = make(name: "DADGAD",
        (.D, 2), (.A, 2), (.D, 3), (.G, 3), (.A, 3), (.D, 4))

    static let halfStepDown = make(name: "Half Step Down",
        (.Eb, 2), (.Ab, 2), (.Eb, 3), (.Ab, 3), (.Bb, 3), (.Eb, 4))
        // Note: Half step down from Db3 should be Eb3 for the 4th string —
        // Standard is E A D G B E, half step down is Eb Ab Db Gb Bb Eb
        // But the spec says: Eb2 Ab2 Db3 Gb3 Bb3 Eb4

    static let builtIns: [GuitarTuning] = [
        standard, dropD, openG, openD, dadgad, halfStepDown
    ]
}
```

**Wait** — the spec says Half Step Down is Eb2 Ab2 Db3 Gb3 Bb3 Eb4. Let me fix that. Db is enharmonic to C#, Gb is enharmonic to F#. Since our Note enum uses Eb/Ab/Bb for flats but Cs/Fs for sharps, we need to use `.Cs` for Db and `.Fs` for Gb (they are the same pitch). Update the halfStepDown:

```swift
    static let halfStepDown = make(name: "Half Step Down",
        (.Eb, 2), (.Ab, 2), (.Cs, 3), (.Fs, 3), (.Bb, 3), (.Eb, 4))
```

This is correct — Cs3 = Db3, Fs3 = Gb3 in equal temperament. The display will show "C#3" and "F#3" instead of "Db3" and "Gb3". This is acceptable since they are the same pitch.

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: All GuitarTuningTests pass

- [x] **Step 5: Commit**

```bash
git add stuner/Models/GuitarTuning.swift stunerTests/GuitarTuningTests.swift
git commit -m "feat: add GuitarTuning model with 6 built-in tuning presets"
```

---

### Task 3: YIN Pitch Detector

**Files:**
- Create: `stuner/Audio/PitchDetector.swift`
- Create: `stunerTests/PitchDetectorTests.swift`

- [x] **Step 1: Write the failing tests**

Create `stunerTests/PitchDetectorTests.swift`:

```swift
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
        // Low frequencies need more samples for accuracy
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
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: Build failure — `PitchDetector` not defined

- [x] **Step 3: Implement YIN pitch detector**

Create `stuner/Audio/PitchDetector.swift`:

```swift
import Accelerate
import Foundation

struct PitchResult: Sendable {
    let frequency: Double
    let confidence: Double
}

enum PitchDetector {
    /// YIN pitch detection algorithm
    /// - Parameters:
    ///   - buffer: Audio sample buffer (mono, Float)
    ///   - sampleRate: Sample rate in Hz (e.g. 44100)
    ///   - threshold: YIN threshold (lower = stricter, default 0.1)
    /// - Returns: Detected pitch and confidence, or nil if no pitch found
    static func detectPitch(
        buffer: [Float],
        sampleRate: Double,
        threshold: Double = 0.1
    ) -> PitchResult? {
        let halfLength = buffer.count / 2

        // Step 1 & 2: Compute the difference function using autocorrelation
        let difference = yinDifference(buffer: buffer, halfLength: halfLength)

        // Step 3: Cumulative mean normalized difference
        let cmnd = cumulativeMeanNormalized(difference: difference, halfLength: halfLength)

        // Step 4: Absolute threshold — find first dip below threshold
        guard let tauEstimate = absoluteThreshold(cmnd: cmnd, halfLength: halfLength, threshold: threshold) else {
            return nil
        }

        // Step 5: Parabolic interpolation for sub-sample accuracy
        let betterTau = parabolicInterpolation(cmnd: cmnd, tau: tauEstimate)

        let frequency = sampleRate / betterTau
        let confidence = 1.0 - Double(cmnd[tauEstimate])

        // Guitar range sanity check: ~60 Hz (below drop-C low string) to ~1400 Hz (high frets on string 1)
        guard frequency > 60.0, frequency < 1400.0 else {
            return nil
        }

        return PitchResult(frequency: frequency, confidence: confidence)
    }

    // MARK: - YIN Steps

    private static func yinDifference(buffer: [Float], halfLength: Int) -> [Float] {
        var difference = [Float](repeating: 0.0, count: halfLength)
        for tau in 0..<halfLength {
            var sum: Float = 0.0
            for i in 0..<halfLength {
                let delta = buffer[i] - buffer[i + tau]
                sum += delta * delta
            }
            difference[tau] = sum
        }
        return difference
    }

    private static func cumulativeMeanNormalized(difference: [Float], halfLength: Int) -> [Float] {
        var cmnd = [Float](repeating: 0.0, count: halfLength)
        cmnd[0] = 1.0
        var runningSum: Float = 0.0
        for tau in 1..<halfLength {
            runningSum += difference[tau]
            cmnd[tau] = difference[tau] * Float(tau) / runningSum
        }
        return cmnd
    }

    private static func absoluteThreshold(cmnd: [Float], halfLength: Int, threshold: Double) -> Int? {
        // Minimum tau: sampleRate / maxFreq. At 44100 Hz, 1400 Hz max → tau >= 31
        let minTau = 2
        for tau in minTau..<halfLength {
            if cmnd[tau] < Float(threshold) {
                // Find the local minimum after crossing threshold
                var minTauLocal = tau
                while minTauLocal + 1 < halfLength && cmnd[minTauLocal + 1] < cmnd[minTauLocal] {
                    minTauLocal += 1
                }
                return minTauLocal
            }
        }
        return nil
    }

    private static func parabolicInterpolation(cmnd: [Float], tau: Int) -> Double {
        guard tau > 0, tau < cmnd.count - 1 else {
            return Double(tau)
        }
        let s0 = Double(cmnd[tau - 1])
        let s1 = Double(cmnd[tau])
        let s2 = Double(cmnd[tau + 1])
        let adjustment = (s2 - s0) / (2.0 * (2.0 * s1 - s2 - s0))
        return Double(tau) + adjustment
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: All PitchDetectorTests pass

- [x] **Step 5: Commit**

```bash
git add stuner/Audio/PitchDetector.swift stunerTests/PitchDetectorTests.swift
git commit -m "feat: add YIN pitch detection algorithm with tests"
```

---

### Task 4: TunerState ViewModel

**Files:**
- Create: `stuner/ViewModels/TunerState.swift`
- Create: `stunerTests/TunerStateTests.swift`

- [x] **Step 1: Write the failing tests**

Create `stunerTests/TunerStateTests.swift`:

```swift
import Testing
@testable import stuner

@Suite("TunerState Tests")
struct TunerStateTests {

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

    @Test("Process pitch updates state - A4 exact")
    func processPitchExact() {
        let state = TunerState()
        state.processPitch(frequency: 440.0, confidence: 0.9)
        #expect(state.detectedFrequency == 440.0)
        #expect(state.detectedNote == .A)
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
        // A4 = 440 Hz, play 445 Hz → should be sharp (positive cents)
        state.processPitch(frequency: 445.0, confidence: 0.9)
        #expect(state.centsOffset > 0)
        #expect(state.centsOffset < 50)
    }

    @Test("Custom A4 affects detection")
    func customA4() {
        let state = TunerState()
        state.a4Frequency = 432.0
        // 432 Hz should now be exactly A4 in tune
        state.processPitch(frequency: 432.0, confidence: 0.9)
        #expect(state.detectedNote == .A)
        #expect(abs(state.centsOffset) < 1.0)
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
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: Build failure — `TunerState` not defined

- [x] **Step 3: Implement TunerState**

Create `stuner/ViewModels/TunerState.swift`:

```swift
import Foundation
import Observation

@Observable
final class TunerState {
    // MARK: - Detection state
    var detectedFrequency: Double?
    var detectedNote: Note?
    var detectedOctave: Int?
    var centsOffset: Double = 0
    var confidence: Double = 0
    var isActive: Bool = false
    var targetString: StringTuning?

    // MARK: - User settings
    var selectedTuning: GuitarTuning
    var selectedString: Int?  // nil = auto-detect, 1-6 = locked to string
    var a4Frequency: Double {
        didSet { UserDefaults.standard.set(a4Frequency, forKey: "a4Frequency") }
    }

    // MARK: - Custom tunings
    private(set) var customTunings: [GuitarTuning] = []

    // MARK: - Reference tone
    var isPlayingTone: Bool = false

    init() {
        let savedA4 = UserDefaults.standard.double(forKey: "a4Frequency")
        self.a4Frequency = savedA4 > 0 ? savedA4 : 440.0
        self.selectedTuning = GuitarTuning.standard
        loadCustomTunings()
        loadSelectedTuning()
    }

    // MARK: - Pitch processing

    func processPitch(frequency: Double, confidence: Double) {
        guard confidence > 0.7 else {
            return
        }

        self.detectedFrequency = frequency
        self.confidence = confidence

        let (note, octave, _) = Note.nearest(to: frequency, a4: a4Frequency)
        self.detectedNote = note
        self.detectedOctave = octave

        // Determine target string
        let target: StringTuning
        if let locked = selectedString,
           let lockedString = selectedTuning.strings.first(where: { $0.stringNumber == locked }) {
            target = lockedString
        } else {
            target = selectedTuning.closestString(to: frequency, a4: a4Frequency)
        }
        self.targetString = target

        // Calculate cents offset from target
        let targetFreq = target.frequency(a4: a4Frequency)
        self.centsOffset = 1200.0 * log2(frequency / targetFreq)
        // Clamp to ±50
        self.centsOffset = max(-50, min(50, self.centsOffset))
    }

    func clearDetection() {
        detectedFrequency = nil
        detectedNote = nil
        detectedOctave = nil
        centsOffset = 0
        confidence = 0
        targetString = nil
    }

    // MARK: - Tuning management

    func selectTuning(_ tuning: GuitarTuning) {
        selectedTuning = tuning
        selectedString = nil
        UserDefaults.standard.set(tuning.id.uuidString, forKey: "selectedTuningId")
    }

    func addCustomTuning(_ tuning: GuitarTuning) {
        customTunings.append(tuning)
        saveCustomTunings()
    }

    func removeCustomTuning(id: UUID) {
        customTunings.removeAll { $0.id == id }
        saveCustomTunings()
        if selectedTuning.id == id {
            selectedTuning = GuitarTuning.standard
        }
    }

    // MARK: - Persistence

    private func saveCustomTunings() {
        if let data = try? JSONEncoder().encode(customTunings) {
            UserDefaults.standard.set(data, forKey: "customTunings")
        }
    }

    private func loadCustomTunings() {
        if let data = UserDefaults.standard.data(forKey: "customTunings"),
           let tunings = try? JSONDecoder().decode([GuitarTuning].self, from: data) {
            customTunings = tunings
        }
    }

    private func loadSelectedTuning() {
        guard let idString = UserDefaults.standard.string(forKey: "selectedTuningId"),
              let id = UUID(uuidString: idString) else { return }
        if let builtIn = GuitarTuning.builtIns.first(where: { $0.id == id }) {
            selectedTuning = builtIn
        } else if let custom = customTunings.first(where: { $0.id == id }) {
            selectedTuning = custom
        }
    }
}
```

**Note:** Built-in tunings use `UUID()` which generates a new ID each launch. For persistence to work, built-in tuning IDs must be stable. Fix by using deterministic UUIDs:

In `stuner/Models/GuitarTuning.swift`, update the `make` helper:

```swift
    private static func make(
        name: String,
        _ s6: (Note, Int), _ s5: (Note, Int), _ s4: (Note, Int),
        _ s3: (Note, Int), _ s2: (Note, Int), _ s1: (Note, Int)
    ) -> GuitarTuning {
        // Deterministic UUID from name so built-in IDs are stable across launches
        let id = UUID(uuidString: "00000000-0000-0000-0000-\(name.lowercased().padding(toLength: 12, withPad: "0", startingAt: 0).prefix(12).map { String(format: "%02x", $0.asciiValue ?? 0) }.joined().prefix(12))")
            ?? UUID()
        return GuitarTuning(id: id, name: name, strings: [
            StringTuning(stringNumber: 6, note: s6.0, octave: s6.1),
            StringTuning(stringNumber: 5, note: s5.0, octave: s5.1),
            StringTuning(stringNumber: 4, note: s4.0, octave: s4.1),
            StringTuning(stringNumber: 3, note: s3.0, octave: s3.1),
            StringTuning(stringNumber: 2, note: s2.0, octave: s2.1),
            StringTuning(stringNumber: 1, note: s1.0, octave: s1.1),
        ], isBuiltIn: true)
    }
```

Actually, a simpler approach — hardcode the UUIDs:

```swift
    static let standard = GuitarTuning(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Standard", strings: makeStrings((.E,2),(.A,2),(.D,3),(.G,3),(.B,3),(.E,4)), isBuiltIn: true)
```

Keep it simple. Use the `make` helper with explicit IDs:

```swift
    private static func make(
        id: Int,
        name: String,
        _ s6: (Note, Int), _ s5: (Note, Int), _ s4: (Note, Int),
        _ s3: (Note, Int), _ s2: (Note, Int), _ s1: (Note, Int)
    ) -> GuitarTuning {
        GuitarTuning(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", id))")!,
            name: name,
            strings: [
                StringTuning(stringNumber: 6, note: s6.0, octave: s6.1),
                StringTuning(stringNumber: 5, note: s5.0, octave: s5.1),
                StringTuning(stringNumber: 4, note: s4.0, octave: s4.1),
                StringTuning(stringNumber: 3, note: s3.0, octave: s3.1),
                StringTuning(stringNumber: 2, note: s2.0, octave: s2.1),
                StringTuning(stringNumber: 1, note: s1.0, octave: s1.1),
            ],
            isBuiltIn: true
        )
    }

    static let standard = make(id: 1, name: "Standard",
        (.E, 2), (.A, 2), (.D, 3), (.G, 3), (.B, 3), (.E, 4))
    static let dropD = make(id: 2, name: "Drop D",
        (.D, 2), (.A, 2), (.D, 3), (.G, 3), (.B, 3), (.E, 4))
    static let openG = make(id: 3, name: "Open G",
        (.D, 2), (.G, 2), (.D, 3), (.G, 3), (.B, 3), (.D, 4))
    static let openD = make(id: 4, name: "Open D",
        (.D, 2), (.A, 2), (.D, 3), (.Fs, 3), (.A, 3), (.D, 4))
    static let dadgad = make(id: 5, name: "DADGAD",
        (.D, 2), (.A, 2), (.D, 3), (.G, 3), (.A, 3), (.D, 4))
    static let halfStepDown = make(id: 6, name: "Half Step Down",
        (.Eb, 2), (.Ab, 2), (.Cs, 3), (.Fs, 3), (.Bb, 3), (.Eb, 4))
```

Apply this change when implementing Task 2 Step 3 (replace the original `make` helper and static properties).

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: All TunerStateTests pass

- [x] **Step 5: Commit**

```bash
git add stuner/ViewModels/TunerState.swift stunerTests/TunerStateTests.swift
git commit -m "feat: add TunerState observable with pitch processing and tuning persistence"
```

---

### Task 5: AudioEngine (Microphone Capture)

**Files:**
- Create: `stuner/Audio/AudioEngine.swift`

No unit tests for this task — it wraps hardware (microphone). Tested via integration on device.

- [x] **Step 1: Create AudioEngine**

Create `stuner/Audio/AudioEngine.swift`:

```swift
import AVFoundation
import Foundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 4096
    private var onPitch: ((PitchResult) -> Void)?

    var sampleRate: Double {
        engine.inputNode.inputFormat(forBus: 0).sampleRate
    }

    func start(onPitch: @escaping (PitchResult) -> Void) throws {
        self.onPitch = onPitch

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        let rate = buffer.format.sampleRate

        if let result = PitchDetector.detectPitch(buffer: samples, sampleRate: rate) {
            onPitch?(result)
        }
    }
}
```

- [x] **Step 2: Build to verify compilation**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [x] **Step 3: Commit**

```bash
git add stuner/Audio/AudioEngine.swift
git commit -m "feat: add AudioEngine for mic capture feeding into PitchDetector"
```

---

### Task 6: ToneGenerator (Reference Tone Playback)

**Files:**
- Create: `stuner/Audio/ToneGenerator.swift`

No unit tests — audio output hardware. Tested on device.

- [x] **Step 1: Create ToneGenerator**

Create `stuner/Audio/ToneGenerator.swift`:

```swift
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
```

- [x] **Step 2: Build to verify compilation**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [x] **Step 3: Commit**

```bash
git add stuner/Audio/ToneGenerator.swift
git commit -m "feat: add ToneGenerator for reference tone sine wave playback"
```

---

### Task 7: Main Tuner View

**Files:**
- Create: `stuner/Views/TunerView.swift`
- Create: `stuner/Views/StringSelectorView.swift`
- Create: `stuner/Views/CentsIndicatorView.swift`

- [x] **Step 1: Create CentsIndicatorView**

Create `stuner/Views/CentsIndicatorView.swift`:

```swift
import SwiftUI

struct CentsIndicatorView: View {
    let centsOffset: Double  // -50 to +50
    let confidence: Double

    private var dotColor: Color {
        let absCents = abs(centsOffset)
        if confidence < 0.7 { return .gray }
        if absCents <= 2 { return .green }
        if absCents <= 10 { return .yellow }
        return .red
    }

    /// Map cents (-50...+50) to position (0...1)
    private var dotPosition: Double {
        guard confidence >= 0.7 else { return 0.5 }
        return (centsOffset + 50.0) / 100.0
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Center tick
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 2, height: 16)
                        .position(x: width / 2, y: 8)

                    // Quarter ticks
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 10)
                        .position(x: width * 0.25, y: 8)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 10)
                        .position(x: width * 0.75, y: 8)

                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                        .position(x: width / 2, y: 24)

                    // Dot
                    Circle()
                        .fill(dotColor)
                        .frame(width: 16, height: 16)
                        .shadow(color: dotColor.opacity(0.4), radius: 6)
                        .position(x: width * dotPosition, y: 24)
                }
            }
            .frame(height: 36)

            // Labels
            HStack {
                Text("FLAT")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                Spacer()
                Text(centsText)
                    .font(.system(size: 11))
                    .foregroundStyle(dotColor)
                Spacer()
                Text("SHARP")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }
        }
        .animation(.easeOut(duration: 0.1), value: centsOffset)
    }

    private var centsText: String {
        guard confidence >= 0.7 else { return "—" }
        let rounded = Int(round(centsOffset))
        if rounded == 0 { return "IN TUNE" }
        return rounded > 0 ? "+\(rounded) cents" : "\(rounded) cents"
    }
}

#Preview {
    VStack(spacing: 40) {
        CentsIndicatorView(centsOffset: 0, confidence: 0.9)
        CentsIndicatorView(centsOffset: 15, confidence: 0.9)
        CentsIndicatorView(centsOffset: -3, confidence: 0.9)
        CentsIndicatorView(centsOffset: 0, confidence: 0.3)
    }
    .padding(40)
    .background(.black)
}
```

- [x] **Step 2: Create StringSelectorView**

Create `stuner/Views/StringSelectorView.swift`:

```swift
import SwiftUI

struct StringSelectorView: View {
    let strings: [StringTuning]       // 6 strings, index 0 = string 6 (low)
    let targetString: StringTuning?   // currently detected/locked string
    let selectedString: Int?          // locked string number (nil = auto)
    let onSelect: (Int?) -> Void      // tap handler — pass string number or nil to unlock

    var body: some View {
        HStack(spacing: 12) {
            ForEach(strings) { string in
                let isTarget = targetString?.stringNumber == string.stringNumber
                let isLocked = selectedString == string.stringNumber

                Button {
                    if isLocked {
                        onSelect(nil)  // tap again to unlock
                    } else {
                        onSelect(string.stringNumber)
                    }
                } label: {
                    Text(string.displayName)
                        .font(.system(size: 14))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(isTarget ? .white : .gray)
                        .background(
                            Circle()
                                .fill(isTarget ? Color.white.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isLocked ? Color.white : (isTarget ? Color.gray : Color.gray.opacity(0.3)),
                                    lineWidth: isLocked ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    let strings = GuitarTuning.standard.strings
    StringSelectorView(
        strings: strings,
        targetString: strings[4],  // B3
        selectedString: nil,
        onSelect: { _ in }
    )
    .padding()
    .background(.black)
}
```

- [x] **Step 3: Create TunerView**

Create `stuner/Views/TunerView.swift`:

```swift
import SwiftUI

struct TunerView: View {
    @State var tunerState: TunerState
    @State private var audioEngine = AudioEngine()
    @State private var toneGenerator = ToneGenerator()
    @State private var showTuningPicker = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                Text("\(tunerState.selectedTuning.name) · A4 = \(Int(tunerState.a4Frequency)) Hz")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .padding(.top, 16)

                Spacer().frame(height: 32)

                // String selector
                StringSelectorView(
                    strings: tunerState.selectedTuning.strings,
                    targetString: tunerState.targetString,
                    selectedString: tunerState.selectedString,
                    onSelect: { stringNum in
                        tunerState.selectedString = stringNum
                    }
                )

                Spacer().frame(height: 48)

                // Detected note
                Text(tunerState.detectedNote?.displayName ?? "—")
                    .font(.system(size: 96, weight: .ultraLight))
                    .foregroundStyle(.white)

                Text(frequencyText)
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)

                Spacer().frame(height: 40)

                // Cents indicator
                CentsIndicatorView(
                    centsOffset: tunerState.centsOffset,
                    confidence: tunerState.confidence
                )
                .padding(.horizontal, 40)

                Spacer()

                // Bottom controls
                HStack(spacing: 48) {
                    controlButton(icon: "speaker.wave.2", label: "Tone", isActive: tunerState.isPlayingTone) {
                        toggleTone()
                    }
                    controlButton(icon: "guitars", label: "Tuning") {
                        showTuningPicker = true
                    }
                    controlButton(icon: "gearshape", label: "Settings") {
                        showSettings = true
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startListening() }
        .onDisappear { stopListening() }
        .sheet(isPresented: $showTuningPicker) {
            TuningPickerView(tunerState: tunerState)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(tunerState: tunerState)
                .presentationDetents([.medium, .large])
        }
    }

    private var frequencyText: String {
        guard let freq = tunerState.detectedFrequency else { return "—" }
        return String(format: "%.1f Hz", freq)
    }

    private func controlButton(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isActive ? Color.blue.opacity(0.3) : Color.white.opacity(0.08))
                    )
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Audio

    private func startListening() {
        tunerState.isActive = true
        do {
            try audioEngine.start { result in
                Task { @MainActor in
                    tunerState.processPitch(frequency: result.frequency, confidence: result.confidence)
                }
            }
        } catch {
            tunerState.isActive = false
        }
    }

    private func stopListening() {
        audioEngine.stop()
        toneGenerator.stop()
        tunerState.isActive = false
    }

    private func toggleTone() {
        if tunerState.isPlayingTone {
            toneGenerator.stop()
            tunerState.isPlayingTone = false
        } else {
            let target = tunerState.targetString ?? tunerState.selectedTuning.strings.first!
            let freq = target.frequency(a4: tunerState.a4Frequency)
            toneGenerator.play(frequency: freq)
            tunerState.isPlayingTone = true
        }
    }
}

#Preview {
    TunerView(tunerState: TunerState())
}
```

- [x] **Step 4: Build to verify compilation**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED (may have warnings for missing TuningPickerView/SettingsView — those come in next task)

Note: If the build fails because TuningPickerView and SettingsView don't exist yet, create placeholder files:

`stuner/Views/TuningPickerView.swift`:
```swift
import SwiftUI
struct TuningPickerView: View {
    var tunerState: TunerState
    var body: some View { Text("Tuning Picker") }
}
```

`stuner/Views/SettingsView.swift`:
```swift
import SwiftUI
struct SettingsView: View {
    var tunerState: TunerState
    var body: some View { Text("Settings") }
}
```

- [x] **Step 5: Commit**

```bash
git add stuner/Views/TunerView.swift stuner/Views/StringSelectorView.swift stuner/Views/CentsIndicatorView.swift stuner/Views/TuningPickerView.swift stuner/Views/SettingsView.swift
git commit -m "feat: add main tuner UI with string selector and cents indicator"
```

---

### Task 8: Tuning Picker and Settings Views

**Files:**
- Modify: `stuner/Views/TuningPickerView.swift`
- Modify: `stuner/Views/SettingsView.swift`

- [x] **Step 1: Implement TuningPickerView**

Replace `stuner/Views/TuningPickerView.swift`:

```swift
import SwiftUI

struct TuningPickerView: View {
    var tunerState: TunerState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(GuitarTuning.builtIns) { tuning in
                        tuningRow(tuning)
                    }
                }

                if !tunerState.customTunings.isEmpty {
                    Section("Custom") {
                        ForEach(tunerState.customTunings) { tuning in
                            tuningRow(tuning)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { tunerState.customTunings[$0].id }
                            ids.forEach { tunerState.removeCustomTuning(id: $0) }
                        }
                    }
                }
            }
            .navigationTitle("Tunings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("+ New") {
                        CustomTuningEditorView(tunerState: tunerState)
                    }
                }
            }
        }
    }

    private func tuningRow(_ tuning: GuitarTuning) -> some View {
        Button {
            tunerState.selectTuning(tuning)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(tuning.name)
                        .foregroundStyle(tunerState.selectedTuning.id == tuning.id ? .blue : .primary)
                    Text(tuning.strings.map(\.displayName).joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if tunerState.selectedTuning.id == tuning.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

struct CustomTuningEditorView: View {
    var tunerState: TunerState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedNotes: [(Note, Int)] = [
        (.E, 2), (.A, 2), (.D, 3), (.G, 3), (.B, 3), (.E, 4)
    ]

    private let allNotes = Note.allCases
    private let octaveRange = 1...6

    var body: some View {
        Form {
            Section("Name") {
                TextField("Tuning name", text: $name)
            }

            Section("Strings") {
                ForEach(0..<6, id: \.self) { index in
                    let stringNum = 6 - index  // index 0 = string 6
                    HStack {
                        Text("String \(stringNum)")
                            .frame(width: 70, alignment: .leading)
                        Spacer()
                        Picker("Note", selection: $selectedNotes[index].0) {
                            ForEach(allNotes, id: \.self) { note in
                                Text(note.displayName).tag(note)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Octave", selection: $selectedNotes[index].1) {
                            ForEach(Array(octaveRange), id: \.self) { oct in
                                Text("\(oct)").tag(oct)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            Section {
                Button("Save Tuning") {
                    saveTuning()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("New Tuning")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveTuning() {
        let strings = selectedNotes.enumerated().map { index, pair in
            StringTuning(stringNumber: 6 - index, note: pair.0, octave: pair.1)
        }
        let tuning = GuitarTuning(name: name.trimmingCharacters(in: .whitespaces), strings: strings)
        tunerState.addCustomTuning(tuning)
        dismiss()
    }
}
```

- [x] **Step 2: Implement SettingsView**

Replace `stuner/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var tunerState: TunerState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Reference Pitch") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("A4 Frequency")
                            Spacer()
                            Text("\(Int(tunerState.a4Frequency)) Hz")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }

                        Slider(
                            value: $tunerState.a4Frequency,
                            in: 420...460,
                            step: 1
                        )

                        HStack {
                            Text("420 Hz")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("460 Hz")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button("Reset to 440 Hz") {
                        tunerState.a4Frequency = 440.0
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

- [x] **Step 3: Build to verify compilation**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [x] **Step 4: Commit**

```bash
git add stuner/Views/TuningPickerView.swift stuner/Views/SettingsView.swift
git commit -m "feat: add tuning picker with custom tuning editor and settings view"
```

---

### Task 9: App Wiring and Microphone Permission

**Files:**
- Modify: `stuner/stunerApp.swift`
- Modify: `stuner/ContentView.swift` (replace contents)
- Create: `stuner/Info.plist`

- [x] **Step 1: Update stunerApp.swift**

Replace `stuner/stunerApp.swift`:

```swift
import SwiftUI

@main
struct stunerApp: App {
    @State private var tunerState = TunerState()

    var body: some Scene {
        WindowGroup {
            TunerView(tunerState: tunerState)
        }
    }
}
```

- [x] **Step 2: Delete ContentView.swift**

Remove `stuner/ContentView.swift` — it is no longer used. TunerView is the root view.

```bash
rm stuner/ContentView.swift
```

- [x] **Step 3: Add microphone permission to Info.plist**

Create `stuner/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSMicrophoneUsageDescription</key>
    <string>stuner needs access to your microphone to detect the pitch of your guitar strings.</string>
</dict>
</plist>
```

Then update the Xcode project build settings to use this Info.plist. In the pbxproj, add to both Debug and Release configurations for the stuner target:

```
INFOPLIST_FILE = stuner/Info.plist;
```

This tells Xcode to merge the custom Info.plist keys with the auto-generated ones (`GENERATE_INFOPLIST_FILE = YES` is still on, so keys from both sources get merged).

- [x] **Step 4: Build to verify compilation**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [x] **Step 5: Run all tests**

Run: `xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: All tests pass

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: wire up app entry point with mic permission and remove boilerplate ContentView"
```

---

### Task 10: Final Build Verification and Cleanup

**Files:**
- May modify any file for compilation fixes

- [x] **Step 1: Full clean build**

```bash
xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' clean build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED with zero errors

- [x] **Step 2: Run all tests**

```bash
xcodebuild -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -30
```

Expected: All tests pass

- [x] **Step 3: Fix any issues found**

If build or tests fail, fix the issues and re-run. Common things to check:
- Swift strict concurrency — audio callbacks may need `@Sendable` or `nonisolated`
- MainActor isolation — `TunerState` properties accessed from audio thread need dispatching
- Missing imports

- [x] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: resolve build warnings and test failures"
```
