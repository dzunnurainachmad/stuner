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
        #expect(cents > 0)
    }

    @Test("Nearest note from frequency - E2")
    func nearestNoteE2() {
        let (note, octave, _) = Note.nearest(to: 82.41, a4: 440.0)
        #expect(note == .E)
        #expect(octave == 2)
    }
}
