# stuner — Guitar Tuner App Design Spec

## Overview

A minimal, clean iOS guitar tuner app built with SwiftUI. Detects pitch via the device microphone using the YIN algorithm, displays how in-tune the detected note is, and supports standard and custom guitar tunings with configurable A4 reference frequency.

## Core Features

### 1. Real-Time Pitch Detection
- Captures audio via `AVAudioEngine` with `AVAudioSession` category `.record`
- Buffer size: 4096 samples at 44.1kHz (~93ms per buffer)
- YIN pitch detection algorithm on each buffer, outputs frequency + confidence (0–1)
- UI only updates when confidence > 0.7 to avoid jitter
- Auto-detect mode: compares detected frequency against all 6 strings in current tuning, highlights closest match
- String lock mode: user taps a specific string circle, detection locks to that target only

### 2. Reference Tone Playback
- Generates sine wave at target frequency via `AVAudioEngine` output node
- Plays the tone for the currently selected/detected string
- User toggles on/off via Tone button

### 3. Tuning Presets
Built-in tunings (always available, not editable):
- **Standard**: E2 A2 D3 G3 B3 E4
- **Drop D**: D2 A2 D3 G3 B3 E4
- **Open G**: D2 G2 D3 G3 B3 D4
- **Open D**: D2 A2 D3 F#3 A3 D4
- **DADGAD**: D2 A2 D3 G3 A3 D4
- **Half Step Down**: Eb2 Ab2 Db3 Gb3 Bb3 Eb4

### 4. Custom Tunings
- User creates named tunings by picking a note + octave for each of 6 strings
- Saved tunings persist across app launches (UserDefaults)
- Custom tunings can be deleted; built-in tunings cannot

### 5. A4 Reference Frequency
- Default: 440 Hz
- Adjustable via slider: 420–460 Hz range
- All pitch calculations use this as the reference
- Persisted across launches

## Architecture

```
┌─────────────┐     ┌────────────────┐     ┌──────────────┐     ┌────────────┐
│ AVAudioEngine│────▶│ PitchDetector  │────▶│ TuningEngine │────▶│ SwiftUI    │
│ (mic input)  │     │ (YIN algorithm)│     │ (cents calc) │     │ Views      │
└─────────────┘     └────────────────┘     └──────────────┘     └────────────┘

┌──────────────┐
│ ToneGenerator│────▶ AVAudioEngine output ────▶ Speaker
└──────────────┘
```

Data flows one direction: Mic → AudioEngine → PitchDetector → TuningEngine → Views (via `@Observable`).

## Data Model

### Note
Enum of 12 chromatic notes: C, C#, D, Eb, E, F, F#, G, Ab, A, Bb, B

### StringTuning
- `stringNumber: Int` (1–6, 1 = highest/thinnest)
- `note: Note`
- `octave: Int`

### GuitarTuning
- `id: UUID`
- `name: String`
- `strings: [StringTuning]` (6 items)
- `isBuiltIn: Bool`

### TunerState (@Observable)
- `detectedFrequency: Double?`
- `detectedNote: Note?`
- `centsOffset: Double` (−50 to +50, 0 = in tune)
- `confidence: Double` (0–1)
- `isActive: Bool`
- `selectedTuning: GuitarTuning`
- `selectedString: Int?` (nil = auto-detect)
- `a4Frequency: Double` (default 440)

### Settings (persisted via UserDefaults)
- `a4Frequency: Double`
- `savedTunings: [GuitarTuning]`
- `selectedTuningId: UUID`

## UI Design

### Main Tuner Screen (dark background, minimal)
Top to bottom:
1. **Header line** — current tuning name + A4 frequency (small, muted text)
2. **String selector** — 6 circles in a row, each showing note+octave. Auto-highlights detected string. Tap to lock to a specific string.
3. **Note display** — large detected note letter (96pt, light weight) + detected frequency below in small muted text
4. **Cents indicator** — horizontal bar with center tick mark. Glowing dot moves left (flat) or right (sharp). Color: green (±2 cents), yellow (±10 cents), red (beyond). Shows "FLAT" / cents value / "SHARP" labels.
5. **Bottom controls** — three icon buttons: Tone (play reference), Tuning (open picker), Settings (open settings)

### Tuning Picker (modal sheet)
- "Tunings" title with "+ New" button
- Built-in section: list of 6 presets, each showing name + string notes
- Custom section: user-created tunings with swipe-to-delete
- Tap to select, checkmark on active tuning

### Settings (modal sheet)
- A4 Frequency: slider (420–460 Hz) with live value display
- Custom tuning creator: name text field + 6 note/octave pickers + Save button
- Each string picker scrolls through note + octave combinations

## Audio Behavior

### Pitch Detection
- Cents formula: `1200 * log2(detectedFreq / targetFreq)`
- YIN algorithm with threshold τ = 0.1 for guitar frequency range
- Minimum confidence 0.7 to update UI

### In-Tune Thresholds
- ±2 cents: green (in tune)
- ±10 cents: yellow (close)
- Beyond ±10 cents: red (needs adjustment)

### Reference Tone
- Pure sine wave at target note frequency
- Respects A4 reference frequency setting
- Toggle on/off, stops when switching strings

## Permissions
- Microphone: required, requested on first launch with explanation string in Info.plist

## File Structure (planned)
```
stuner/
  stunerApp.swift
  Models/
    Note.swift
    GuitarTuning.swift
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
  Utilities/
    TuningPresets.swift
```
