import SwiftUI

struct TuningPickerView: View {
    var tunerState: TunerState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(GuitarTuning.builtIns) { tuning in
                        tuningRow(tuning)
                    }
                }

                if !tunerState.customTunings.isEmpty {
                    Section("Custom") {
                        ForEach(tunerState.customTunings) { tuning in
                            tuningRow(tuning)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { tunerState.customTunings[$0].id }
                            ids.forEach { tunerState.removeCustomTuning(id: $0) }
                        }
                    }
                }
            }
            .navigationTitle("Tunings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("+ New") {
                        CustomTuningEditorView(tunerState: tunerState)
                    }
                }
            }
        }
    }

    private func tuningRow(_ tuning: GuitarTuning) -> some View {
        Button {
            tunerState.selectTuning(tuning)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(tuning.name)
                        .foregroundStyle(tunerState.selectedTuning.id == tuning.id ? .blue : .primary)
                    Text(tuning.strings.map(\.displayName).joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if tunerState.selectedTuning.id == tuning.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

struct CustomTuningEditorView: View {
    var tunerState: TunerState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedNotes: [(Note, Int)] = [
        (.E, 2), (.A, 2), (.D, 3), (.G, 3), (.B, 3), (.E, 4)
    ]

    private let allNotes = Note.allCases
    private let octaveRange = 1...6

    var body: some View {
        Form {
            Section("Name") {
                TextField("Tuning name", text: $name)
            }

            Section("Strings") {
                ForEach(0..<6, id: \.self) { index in
                    let stringNum = 6 - index  // index 0 = string 6
                    HStack {
                        Text("String \(stringNum)")
                            .frame(width: 70, alignment: .leading)
                        Spacer()
                        Picker("Note", selection: $selectedNotes[index].0) {
                            ForEach(allNotes, id: \.self) { note in
                                Text(note.displayName).tag(note)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Octave", selection: $selectedNotes[index].1) {
                            ForEach(Array(octaveRange), id: \.self) { oct in
                                Text("\(oct)").tag(oct)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            Section {
                Button("Save Tuning") {
                    saveTuning()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("New Tuning")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveTuning() {
        let strings = selectedNotes.enumerated().map { index, pair in
            StringTuning(stringNumber: 6 - index, note: pair.0, octave: pair.1)
        }
        let tuning = GuitarTuning(name: name.trimmingCharacters(in: .whitespaces), strings: strings)
        tunerState.addCustomTuning(tuning)
        dismiss()
    }
}
