import SwiftUI

struct EditButtonsSheet: View {
    let mode: PinMode
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var buttons: [ButtonConfig] = []

    private func buttonBinding(_ id: UUID) -> Binding<ButtonConfig> {
        Binding(
            get: { buttons.first { $0.id == id } ?? ButtonConfig(name: "", color: "blue", index: 0, mode: self.mode) },
            set: { newValue in
                if let idx = buttons.firstIndex(where: { $0.id == id }) {
                    buttons[idx] = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(buttons) { button in
                    if button.isGrowthStageButton {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.fromString(button.color).gradient)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Circle().stroke(.primary.opacity(0.15), lineWidth: 1)
                                }

                            Text(button.name)
                                .font(.headline)

                            Spacer()

                            Text(button.index < 4 ? "Left" : "Right")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(.capsule)

                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ButtonConfigRow(config: buttonBinding(button.id))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(mode.rawValue) Buttons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveButtons()
                        dismiss()
                    }
                }
            }
            .onAppear {
                buttons = store.buttonsForMode(mode)
            }
        }
    }

    private func saveButtons() {
        switch mode {
        case .repairs:
            store.updateRepairButtons(buttons)
        case .growth:
            store.updateGrowthButtons(buttons)
        }
    }
}

struct ButtonConfigRow: View {
    @Binding var config: ButtonConfig
    @State private var showColorPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    showColorPicker.toggle()
                } label: {
                    Circle()
                        .fill(Color.fromString(config.color).gradient)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle().stroke(.primary.opacity(0.15), lineWidth: 1)
                        }
                }

                TextField("Button Name", text: $config.name)
                    .font(.headline)

                Text(config.index < 4 ? "Left" : "Right")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.capsule)
            }

            if showColorPicker {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Color.availableColors, id: \.name) { item in
                            Button {
                                config.color = item.name
                                showColorPicker = false
                            } label: {
                                Circle()
                                    .fill(item.color.gradient)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if config.color == item.name {
                                            Circle().stroke(.primary, lineWidth: 2)
                                        }
                                    }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.vertical, 4)
    }
}
