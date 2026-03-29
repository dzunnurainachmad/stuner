# stuner — Guitar Tuner App Design Spec

## Overview

A minimal, clean iOS guitar tuner app built with SwiftUI. Detects pitch via the device microphone using the YIN algorithm, displays how in-tune the detected note is, and supports standard and custom guitar tunings with configurable A4 reference frequency.

## Core Features

### 1. Real-Time Pitch Detection
- Captures audio via `AVAudioEngine` with `AVAudioSession` category `.playAndRecord` (supports simultaneous tone playback)
- Buffer size: 4096 samples at 44.1kHz (~93ms per buffer)
- YIN pitch detection algorithm on each buffer using Accelerate (vDSP), outputs frequency + confidence (0–1)
- Sub-octave correction in YIN: after finding the first CMND dip, checks half-period for a better fundamental match (fixes E4/B3 octave-down jumps while protecting E2/G3)
- Noise gate: ignores buffers with RMS < 0.005
- UI only updates when confidence > 0.7 to avoid jitter
- Pitch detection paused while reference tone is playing (avoids mic feedback interference)
- Auto-detect mode: compares detected frequency against all 6 strings in current tuning, highlights closest match
- String lock mode: user taps a specific string circle, detection locks to that target only
- Debounced string switching: requires 4 consecutive confirmations before switching target string
- Octave jump correction: detects and rejects octave/5th harmonic jumps using stable frequency tracking with NSLock (stableThreshold = 2, EMA smoothing 80/20)

### 2. Reference Tone Playback
- Generates sine wave + harmonics (2x, 3x) at target frequency via `AVAudioSourceNode` render callback
- Harmonics improve audibility on phone speakers for low frequencies
- Amplitude boost for low frequencies (up to 2x) compensating for speaker rolloff
- Smooth frequency transitions via exponential moving average
- Fade-in/fade-out envelope for clean start/stop
- Plays the tone for the currently selected/detected string
- User toggles on/off via Tone button

### 3. Tuning Presets
Built-in tunings (always available, not editable):
- **Standard**: E2 A2 D3 G3 B3 E4
- **Drop D**: D2 A2 D3 G3 B3 E4
- **Open G**: D2 G2 D3 G3 B3 D4
- **Open D**: D2 A2 D3 F#3 A3 D4
- **DADGAD**: D2 A2 D3 G3 A3 D4
- **Half Step Down**: Eb2 Ab2 C#3 F#3 Bb3 Eb4

### 4. Custom Tunings
- User creates named tunings by picking a note + octave for each of 6 strings
- Saved tunings persist across app launches (UserDefaults, JSON-encoded)
- Custom tunings can be deleted; built-in tunings cannot

### 5. A4 Reference Frequency
- Default: 440 Hz
- Adjustable via slider: 420–460 Hz range, step 1
- All pitch calculations use this as the reference
- Persisted across launches via UserDefaults

## Architecture

```
┌─────────────┐     ┌────────────────┐     ┌──────────────┐     ┌────────────┐
│ AVAudioEngine│────▶│ PitchDetector  │────▶│  TunerState  │────▶│ SwiftUI    │
│ (mic input)  │     │ (YIN + vDSP)  │     │ (@Observable)│     │ Views      │
└─────────────┘     └────────────────┘     └──────────────┘     └────────────┘

┌──────────────┐
│ ToneGenerator│────▶ AVAudioSourceNode ────▶ Speaker
└──────────────┘
```

Data flows one direction: Mic → AudioEngine → PitchDetector → TunerState → Views (via `@Observable`).

Thread safety: AudioEngine callback uses `nonisolated(unsafe)` and dispatches to main thread via `Task { @MainActor in ... }`. PitchDetector uses NSLock for octave correction state.

## Data Model

### Note
Enum of 12 chromatic notes: C, C#, D, Eb, E, F, F#, G, Ab, A, Bb, B
- `frequency(octave:a4:)` — equal temperament calculation
- `nearest(to:a4:)` — inverse: frequency → (note, octave, cents)

### StringTuning
- `stringNumber: Int` (1–6, 1 = highest/thinnest)
- `note: Note`
- `octave: Int`
- `displayName: String` — computed, e.g. "E2"
- `frequency(a4:)` — delegates to Note

### GuitarTuning
- `id: UUID` (deterministic for built-ins)
- `name: String`
- `strings: [StringTuning]` (6 items, index 0 = string 6 low, index 5 = string 1 high)
- `isBuiltIn: Bool`
- `closestString(to:a4:)` — log2-based frequency distance

### TunerState (@Observable)
- `detectedFrequency: Double?`
- `detectedNote: Note?`
- `detectedOctave: Int?`
- `centsOffset: Double` (clamped −50 to +50, 0 = in tune)
- `confidence: Double` (0–1)
- `isActive: Bool`
- `targetString: StringTuning?` — detected/locked string
- `selectedTuning: GuitarTuning`
- `selectedString: Int?` (nil = auto-detect, 1–6 = locked)
- `a4Frequency: Double` (default 440, persisted via didSet)
- `customTunings: [GuitarTuning]` (JSON-persisted)
- `isPlayingTone: Bool` (pitch detection paused when true)
- String switch debounce: `switchCandidate`, `switchCount`, `switchThreshold` (4)

### Persistence (UserDefaults)
- `a4Frequency: Double`
- `customTunings: Data` (JSON-encoded [GuitarTuning])
- `selectedTuningId: String` (UUID string)

## UI Design

### Main Tuner Screen (dark background, minimal)

**Portrait layout** — top to bottom:
1. **Header line** — current tuning name + A4 frequency (11pt, muted gray text)
2. **Auto/Manual toggle** — capsule segmented control
3. **String selector** — 6 circles in a row, each showing note+octave. Auto-highlights detected string (white). Locked string gets thicker border. Tap to lock/unlock.
4. **Note display** — large detected note letter (96pt, ultraLight weight) + detected frequency below in small muted text (14pt)
5. **Cents indicator** — horizontal bar with center tick mark. Glowing dot moves left (flat) or right (sharp). Color: green (±2 cents), yellow (±10 cents), red (beyond). Shows "FLAT" / cents value or "IN TUNE" / "SHARP" labels.
6. **Bottom controls** — three icon buttons with labels: Tone (speaker.wave.2), Tuning (guitars), Settings (gearshape). Active tone button shows blue background.

**Landscape layout** — two-column HStack (adapts via `verticalSizeClass == .compact`):
- **Left column**: note display (64pt), frequency label, bottom controls
- **Right column**: header, Auto/Manual toggle, string selector, cents indicator

### Tuning Picker (modal sheet, .medium/.large detents)
- NavigationStack with List
- Built-in section: 6 presets, each showing name + string notes (caption)
- Custom section: user-created tunings with swipe-to-delete
- Tap to select, checkmark on active tuning
- "+ New" navigation button → CustomTuningEditorView (name field + 6 note/octave pickers + Save)

### Settings (modal sheet, .medium/.large detents)
- Form with "Reference Pitch" section
- A4 Frequency: slider (420–460 Hz, step 1) with live value display
- "Reset to 440 Hz" button

## Audio Behavior

### Pitch Detection
- Cents formula: `1200 * log2(detectedFreq / targetFreq)`
- YIN algorithm with threshold 0.2
- Cumulative mean normalized difference for pitch-invariant comparison
- Parabolic interpolation for sub-sample accuracy
- Sub-octave correction: after finding first CMND dip below threshold, checks half-period for a better fundamental. Applies only when full-period CMND > threshold×0.5 (moderate match), preventing false correction on strong fundamentals like E2
- Detection range: ~60–1400 Hz (guitar fundamentals)
- Minimum confidence 0.7 to update UI
- Pitch detection paused while reference tone is playing to avoid speaker-to-mic feedback
- Readings >200 cents off current target are rejected (unless debounce confirms switch)
- Octave jump correction: EMA smoothing (80/20), stable frequency locks after 2 consistent readings

### In-Tune Thresholds
- ±2 cents: green (in tune)
- ±10 cents: yellow (close)
- Beyond ±10 cents: red (needs adjustment)
- Below 0.7 confidence: gray dot

### Reference Tone
- Sine wave fundamental + 2nd and 3rd harmonics
- Harmony mix varies: more harmonics for low notes, purer sine for high notes
- Respects A4 reference frequency setting
- Toggle on/off, updates frequency when switching strings while playing

## Permissions
- Microphone: required, requested on first launch
- Info.plist key: `NSMicrophoneUsageDescription` = "stuner needs access to your microphone to detect the pitch of your guitar strings."

## File Structure
```
stuner/
  stunerApp.swift
  ContentView.swift            (unused legacy file)
  Models/
    Note.swift
    GuitarTuning.swift
  ViewModels/
    TunerState.swift
  Audio/
    AudioEngine.swift
    PitchDetector.swift
    ToneGenerator.swift
  Views/
    TunerView.swift
    StringSelectorView.swift
    CentsIndicatorView.swift
    TuningPickerView.swift
    SettingsView.swift
```

## Testing

### Unit Tests (Swift Testing framework)
- **NoteTests** — 12 tests: frequency calculations, display names, nearest note detection
- **GuitarTuningTests** — 8 tests: string properties, built-in tunings, codability, closest string matching
- **TunerStateTests** — 15 tests (.serialized): pitch processing, confidence filtering, string locking, debounce, persistence, tone-playing pauses detection
- **PitchDetectorTests** — 12 tests (.serialized): YIN detection on generated sine waves, sub-octave correction, octave jump correction, harmonics handling

### UI Tests (XCTest/XCUITest)
- 12 functional tests covering all interactive elements
- Launch arguments reset UserDefaults for deterministic state: `-selectedTuningId ""`, `-a4Frequency "0"`
- All interactive elements have `.accessibilityIdentifier()` for reliable test queries
- Tests run on real device only (no simulator)
