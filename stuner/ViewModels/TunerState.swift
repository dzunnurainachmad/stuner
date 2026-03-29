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
        didSet {
            UserDefaults.standard.set(a4Frequency, forKey: "a4Frequency")
            PitchDetector.reset()
            clearDetection()
        }
    }

    // MARK: - Custom tunings
    private(set) var customTunings: [GuitarTuning] = []

    // MARK: - Reference tone
    var isPlayingTone: Bool = false

    // MARK: - String switch debounce
    private var switchCandidate: Int?
    private var switchCount: Int = 0
    private let switchThreshold = 4

    init() {
        let savedA4 = UserDefaults.standard.double(forKey: "a4Frequency")
        self.a4Frequency = savedA4 > 0 ? savedA4 : 440.0
        self.selectedTuning = GuitarTuning.standard
        loadCustomTunings()
        loadSelectedTuning()
    }

    // MARK: - Pitch processing

    func processPitch(frequency: Double, confidence: Double) {
        guard confidence > 0.7, !isPlayingTone else {
            return
        }

        // If we already have a target, ignore readings that are way off (likely harmonics)
        if let current = targetString {
            let currentCents = abs(1200.0 * log2(frequency / current.frequency(a4: a4Frequency)))
            // More than 200 cents off current target and not locked — likely a bad detection
            if currentCents > 200 && selectedString == nil {
                // Still count towards switching
                let closest = selectedTuning.closestString(to: frequency, a4: a4Frequency)
                if closest.stringNumber != current.stringNumber {
                    if switchCandidate == closest.stringNumber {
                        switchCount += 1
                    } else {
                        switchCandidate = closest.stringNumber
                        switchCount = 1
                    }
                    if switchCount >= switchThreshold {
                        // Confirmed new string — fall through to update
                    } else {
                        return  // Skip this reading
                    }
                }
            }
        }

        self.detectedFrequency = frequency
        self.confidence = confidence

        let (note, octave, _) = Note.nearest(to: frequency, a4: a4Frequency)
        self.detectedNote = note
        self.detectedOctave = octave

        // Determine target string with debounced switching
        let target: StringTuning
        if let locked = selectedString,
           let lockedString = selectedTuning.strings.first(where: { $0.stringNumber == locked }) {
            target = lockedString
        } else {
            let closest = selectedTuning.closestString(to: frequency, a4: a4Frequency)
            if let current = targetString, current.stringNumber != closest.stringNumber {
                if switchCandidate == closest.stringNumber {
                    switchCount += 1
                } else {
                    switchCandidate = closest.stringNumber
                    switchCount = 1
                }
                if switchCount >= switchThreshold {
                    target = closest
                    switchCandidate = nil
                    switchCount = 0
                } else {
                    target = current
                }
            } else {
                target = closest
                switchCandidate = nil
                switchCount = 0
            }
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
        PitchDetector.reset()
        clearDetection()
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
