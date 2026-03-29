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
        audioEngine.start { result in
            Task { @MainActor in
                tunerState.processPitch(frequency: result.frequency, confidence: result.confidence)
            }
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
