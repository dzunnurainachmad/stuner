# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

This is an Xcode iOS project (deployment target iOS 18.0+) with no external dependencies.

**Build:** Open `stuner.xcodeproj` in Xcode and build (Cmd+B). No CocoaPods/SPM setup needed.

**Unit tests** use Swift Testing framework (not XCTest):
```bash
xcodebuild test -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS,name=<device_name>' -only-testing:stunerTests
```

**UI tests** use XCTest:
```bash
xcodebuild test -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS,name=<device_name>' -only-testing:stunerUITests
```

**Run a single test:**
```bash
xcodebuild test -project stuner.xcodeproj -scheme stuner -destination 'platform=iOS,name=<device_name>' -only-testing:stunerTests/NoteTests/testA4Frequency
```

**Important:** Never use the iOS Simulator. The user tests exclusively on a real iPhone device.

## Architecture

Audio pipeline: `Microphone → AVAudioEngine (AudioEngine) → PitchDetector (YIN algorithm, vDSP) → TunerState.processPitch() → SwiftUI views`

- **Models/** — `Note` enum (12 chromatic notes, frequency math) and `GuitarTuning`/`StringTuning` structs (6 built-in tunings, custom tuning support). All `Codable + Sendable`.
- **ViewModels/TunerState.swift** — `@Observable` class holding all app state. Handles pitch processing with debounced string switching (8-confirmation threshold), cents calculation (clamped ±50), and UserDefaults persistence (A4 frequency, selected tuning, custom tunings).
- **Audio/** — `AudioEngine` (mic input, 4096-sample buffers, noise gate RMS<0.005), `PitchDetector` (YIN autocorrelation with octave jump correction via NSLock-protected state machine), `ToneGenerator` (sine + harmonics reference tone with amplitude boost for low frequencies).
- **Views/** — `TunerView` (main screen, owns AudioEngine/ToneGenerator), `StringSelectorView` (6 tappable circles), `CentsIndicatorView` (color-coded offset bar), `TuningPickerView` (built-in + custom tuning selection), `SettingsView` (A4 slider 420-460Hz).

## Key Patterns

- `@Observable` (Observation framework) on TunerState — no @Published needed, views react automatically
- Audio callbacks dispatch to main thread via `Task { @MainActor in ... }`
- `nonisolated(unsafe)` on AudioEngine's callback + NSLock in PitchDetector for thread safety
- UI tests reset UserDefaults via launch arguments (`-selectedTuningId ""`, `-a4Frequency "0"`) to ensure deterministic state
- All UI-testable elements have `.accessibilityIdentifier()` set

## Testing Notes

- Unit tests for TunerState and PitchDetector are marked `.serialized` to avoid race conditions
- PitchDetector tests reset state before each test case
- UI tests require microphone permission to be pre-granted on the device
- Confidence threshold for pitch detection is 0.7
