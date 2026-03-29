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

    private var semitonesFromA: Int {
        (rawValue - Note.A.rawValue)
    }

    func frequency(octave: Int, a4: Double = 440.0) -> Double {
        let semitonesFromA4 = Double(semitonesFromA) + Double(octave - 4) * 12.0
        return a4 * pow(2.0, semitonesFromA4 / 12.0)
    }

    static func nearest(to frequency: Double, a4: Double = 440.0) -> (note: Note, octave: Int, cents: Double) {
        let semitonesFromA4 = 12.0 * log2(frequency / a4)
        let roundedSemitones = Int(round(semitonesFromA4))
        let cents = (semitonesFromA4 - Double(roundedSemitones)) * 100.0

        let noteIndex = ((roundedSemitones % 12) + 12 + Note.A.rawValue) % 12
        let octaveOffset = (roundedSemitones + Note.A.rawValue >= 0)
            ? (roundedSemitones + Note.A.rawValue) / 12
            : (roundedSemitones + Note.A.rawValue - 11) / 12
        let octave = 4 + octaveOffset

        let note = Note(rawValue: noteIndex)!
        return (note, octave, cents)
    }
}
