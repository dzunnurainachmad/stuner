import SwiftUI

struct SettingsView: View {
    @Bindable var tunerState: TunerState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Reference Pitch") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("A4 Frequency")
                            Spacer()
                            Text("\(Int(tunerState.a4Frequency)) Hz")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }

                        Slider(
                            value: $tunerState.a4Frequency,
                            in: 420...460,
                            step: 1
                        )

                        HStack {
                            Text("420 Hz")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("460 Hz")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button("Reset to 440 Hz") {
                        tunerState.a4Frequency = 440.0
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
