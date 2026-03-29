import Foundation
import Testing
@testable import stuner

@Suite("GuitarTuning Tests")
@MainActor
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
