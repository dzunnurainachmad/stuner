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

    static let builtIns: [GuitarTuning] = [
        standard, dropD, openG, openD, dadgad, halfStepDown
    ]
}
