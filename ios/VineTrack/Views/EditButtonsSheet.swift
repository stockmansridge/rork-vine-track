import SwiftUI

struct EditButtonsSheet: View {
    let mode: PinMode
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var buttons: [ButtonConfig] = []
    @State private var selectedTemplateId: UUID? = nil
    @State private var showTemplatePicker: Bool = false

    private var hasDuplicateColors: Bool {
        let colors = pairedRows.map { $0.left.color.lowercased() }
        return Set(colors).count != colors.count
    }

    private var pairedRows: [(left: ButtonConfig, right: ButtonConfig)] {
        let sorted = buttons.sorted { $0.index < $1.index }
        let leftButtons = sorted.filter { $0.index < 4 }
        let rightButtons = sorted.filter { $0.index >= 4 }
        return zip(leftButtons, rightButtons).map { ($0, $1) }
    }

    private var templates: [ButtonTemplate] {
        store.buttonTemplates(for: mode)
    }

    private var activeTemplate: ButtonTemplate? {
        guard let id = selectedTemplateId else { return nil }
        return templates.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            List {
                if !templates.isEmpty {
                    templateSection
                }

                buttonRowsSection

                previewSection
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
                    .disabled(hasDuplicateColors)
                }
            }
            .onAppear {
                buttons = store.buttonsForMode(mode)
                if mode == .repairs {
                    store.ensureDefaultRepairTemplate()
                } else {
                    store.ensureDefaultGrowthTemplate()
                }
                matchActiveTemplate()
            }
        }
    }

    private var templateSection: some View {
        Section {
            ForEach(templates) { template in
                Button {
                    applyTemplate(template)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedTemplateId == template.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedTemplateId == template.id ? .blue : .secondary)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            HStack(spacing: 6) {
                                ForEach(Array(template.entries.enumerated()), id: \.offset) { _, entry in
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(Color.fromString(entry.color).gradient)
                                            .frame(width: 10, height: 10)
                                        Text(entry.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                }
            }
        } header: {
            Text("Template")
        } footer: {
            Text("Select a template to apply, or edit the rows below directly.")
        }
    }

    private var buttonRowsSection: some View {
        Section {
            ForEach(0..<min(pairedRows.count, 4), id: \.self) { rowIndex in
                pairedRowEditor(rowIndex: rowIndex)
            }
        } header: {
            Text("Button Rows (Paired Left & Right)")
        } footer: {
            if hasDuplicateColors {
                Label("Each button must have a unique colour for filtering and identification.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                Text("Each row is paired — the same name and colour applies to both the left and right button.")
            }
        }
    }

    private func pairedRowEditor(rowIndex: Int) -> some View {
        let leftIndex = buttons.firstIndex(where: { $0.index == rowIndex }) ?? 0
        let rightIndex = buttons.firstIndex(where: { $0.index == rowIndex + 4 }) ?? 0

        return PairedButtonRow(
            rowNumber: rowIndex + 1,
            name: Binding(
                get: { buttons[leftIndex].name },
                set: { newValue in
                    buttons[leftIndex].name = newValue
                    buttons[rightIndex].name = newValue
                    selectedTemplateId = nil
                }
            ),
            color: Binding(
                get: { buttons[leftIndex].color },
                set: { newValue in
                    buttons[leftIndex].color = newValue
                    buttons[rightIndex].color = newValue
                    selectedTemplateId = nil
                }
            ),
            isGrowthStageButton: buttons[leftIndex].isGrowthStageButton,
            isGrowthMode: mode == .growth,
            usedColors: usedColors(excluding: rowIndex)
        )
    }

    private func usedColors(excluding rowIndex: Int) -> Set<String> {
        var colors: Set<String> = []
        for row in pairedRows.enumerated() {
            if row.offset != rowIndex {
                colors.insert(row.element.left.color.lowercased())
            }
        }
        return colors
    }

    private var previewSection: some View {
        Section {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("LEFT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(pairedRows.indices, id: \.self) { i in
                        previewButton(name: pairedRows[i].left.name, color: pairedRows[i].left.color)
                    }
                }
                VStack(spacing: 4) {
                    Text("RIGHT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(pairedRows.indices, id: \.self) { i in
                        previewButton(name: pairedRows[i].right.name, color: pairedRows[i].right.color)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Preview")
        }
    }

    private func previewButton(name: String, color: String) -> some View {
        let isLight = ["yellow", "white", "cyan", "lime"].contains(color.lowercased())
        return Text(name.isEmpty ? "Untitled" : name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isLight ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.fromString(color).gradient, in: .rect(cornerRadius: 8))
    }

    private func applyTemplate(_ template: ButtonTemplate) {
        guard let vid = store.selectedVineyardId else { return }
        buttons = template.toButtonConfigs(for: vid)
        selectedTemplateId = template.id
    }

    private func matchActiveTemplate() {
        for template in templates {
            let entries = template.entries.prefix(4)
            let leftButtons = buttons.sorted { $0.index < $1.index }.filter { $0.index < 4 }
            if entries.count == leftButtons.count {
                let matches = zip(entries, leftButtons).allSatisfy { entry, btn in
                    entry.name == btn.name && entry.color.lowercased() == btn.color.lowercased()
                }
                if matches {
                    selectedTemplateId = template.id
                    return
                }
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

struct PairedButtonRow: View {
    let rowNumber: Int
    @Binding var name: String
    @Binding var color: String
    let isGrowthStageButton: Bool
    let isGrowthMode: Bool
    let usedColors: Set<String>
    @State private var showColorPicker: Bool = false

    private var hasDuplicateColor: Bool {
        usedColors.contains(color.lowercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    if !isGrowthStageButton {
                        showColorPicker.toggle()
                    }
                } label: {
                    Circle()
                        .fill(Color.fromString(color).gradient)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle().stroke(.primary.opacity(0.15), lineWidth: 1)
                        }
                }

                if isGrowthStageButton {
                    Text(name)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Button Name", text: $name)
                        .font(.headline)
                }

                Text("Row \(rowNumber)")
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
                            let isUsed = usedColors.contains(item.name.lowercased())
                            Button {
                                color = item.name
                                showColorPicker = false
                            } label: {
                                Circle()
                                    .fill(item.color.gradient)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if color == item.name {
                                            Circle().stroke(.primary, lineWidth: 2)
                                        }
                                    }
                                    .opacity(isUsed ? 0.3 : 1.0)
                            }
                            .disabled(isUsed)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if hasDuplicateColor {
                Text("Duplicate colour")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
