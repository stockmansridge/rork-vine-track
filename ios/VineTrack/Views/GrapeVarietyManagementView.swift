import SwiftUI

struct GrapeVarietyManagementView: View {
    @Environment(DataStore.self) private var store
    @State private var showAddSheet: Bool = false
    @State private var editingVariety: GrapeVariety?

    private var sortedVarieties: [GrapeVariety] {
        store.grapeVarieties.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedVarieties) { variety in
                    Button {
                        editingVariety = variety
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(variety.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Optimal: \(Int(variety.optimalGDD)) GDD")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteGrapeVariety(variety)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Master Variety List")
            } footer: {
                Text("Optimal GDD (Growing Degree Days, base 10°C) represents the heat units typically needed for a variety to reach harvest ripeness. Values are approximate — adjust for your climate and style.")
            }
        }
        .navigationTitle("Grape Varieties")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            EditGrapeVarietySheet(variety: nil)
        }
        .sheet(item: $editingVariety) { variety in
            EditGrapeVarietySheet(variety: variety)
        }
    }
}

struct EditGrapeVarietySheet: View {
    let variety: GrapeVariety?
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var optimalGDDText: String = "1400"

    private var isEditing: Bool { variety != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Chardonnay", text: $name)
                        .autocorrectionDisabled()
                }

                Section {
                    HStack {
                        Text("Optimal GDD")
                        Spacer()
                        TextField("1400", text: $optimalGDDText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                        Text("°C·days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Ripeness Target")
                } footer: {
                    Text("Growing Degree Days (base 10°C) required to reach harvest ripeness.")
                }
            }
            .navigationTitle(isEditing ? "Edit Variety" : "New Variety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let variety {
                    name = variety.name
                    optimalGDDText = "\(Int(variety.optimalGDD))"
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let gdd = Double(optimalGDDText) ?? 1400
        if var existing = variety {
            existing.name = trimmedName
            existing.optimalGDD = gdd
            store.updateGrapeVariety(existing)
        } else {
            let new = GrapeVariety(name: trimmedName, optimalGDD: gdd)
            store.addGrapeVariety(new)
        }
    }
}
