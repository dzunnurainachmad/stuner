# stuner

A guitar tuner app for iOS built with SwiftUI. Detects pitch in real-time using the YIN algorithm and helps you tune your guitar with visual feedback.

## Features

- **Real-time pitch detection** — YIN autocorrelation algorithm via Apple's Accelerate framework (vDSP) for accurate, low-latency note detection
- **Auto & Manual modes** — automatically detect which string you're playing, or lock to a specific string
- **Visual tuning feedback** — color-coded cents indicator (green = in tune, yellow = close, red = off) with smooth animations
- **Reference tone playback** — play the target pitch through your phone speaker with harmonics for better audibility on small speakers
- **Multiple tunings** — 6 built-in tunings (Standard, Drop D, Open G, Open D, DADGAD, Half Step Down) plus custom tuning support
- **Adjustable A4 reference** — configure reference pitch from 420 Hz to 460 Hz

## Requirements

- iOS 18.0+
- Xcode 16+
- Microphone access (for pitch detection)

## Getting Started

1. Clone the repository
2. Open `stuner.xcodeproj` in Xcode
3. Select your device and build (Cmd+R)

No external dependencies — no CocoaPods or SPM packages required.

## How It Works

```
Microphone → AVAudioEngine → YIN Pitch Detection → Note Matching → SwiftUI Display
                                                  ↓
                                        Octave Jump Correction
                                        String Switch Debouncing
```

The app captures audio in 4096-sample buffers (~93ms at 44.1kHz), runs the YIN algorithm to detect the fundamental frequency, matches it to the nearest string in the selected tuning, and displays the cents offset with color-coded visual feedback. A debouncing mechanism (8 consecutive confirmations) prevents jittery string switching.

## Project Structure

```
stuner/
├── Models/          # Note, StringTuning, GuitarTuning
├── ViewModels/      # TunerState (@Observable)
├── Views/           # SwiftUI views (Tuner, StringSelector, CentsIndicator, etc.)
└── Audio/           # AudioEngine, PitchDetector (YIN), ToneGenerator
```

## License

This project is for personal/educational use.
