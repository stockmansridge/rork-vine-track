import SwiftUI
import UIKit

struct YieldDeterminationCalculatorView: View {
    @Environment(DataStore.self) private var store

    enum PruneMethod: String, CaseIterable, Identifiable {
        case spur = "Spur"
        case cane = "Cane"
        var id: String { rawValue }
    }

    @State private var selectedPaddockId: UUID?
    @State private var pruneMethod: PruneMethod = .spur
    @State private var bunchesPerBudText: String = "1.5"

    // Spur inputs
    @State private var budsPerSpurText: String = "2"
    @State private var spursPerVineText: String = "20"

    // Cane inputs
    @State private var budsPerCaneText: String = "10"
    @State private var canesPerVineText: String = "4"

    @State private var vinesPerHaText: String = ""
    @State private var bunchWeightText: String = "120"

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case bunchesPerBud, budsPerSpur, spursPerVine, budsPerCane, canesPerVine, vinesPerHa, bunchWeight
    }

    private var vineyardPaddocks: [Paddock] {
        guard let vid = store.selectedVineyard?.id else { return store.paddocks }
        return store.paddocks.filter { $0.vineyardId == vid }
    }

    private var selectedPaddock: Paddock? {
        guard let id = selectedPaddockId else { return nil }
        return store.paddocks.first(where: { $0.id == id })
    }

    private var bunchesPerBud: Double { parse(bunchesPerBudText) }
    private var budsPerSpur: Double { parse(budsPerSpurText) }
    private var spursPerVine: Double { parse(spursPerVineText) }
    private var budsPerCane: Double { parse(budsPerCaneText) }
    private var canesPerVine: Double { parse(canesPerVineText) }
    private var vinesPerHa: Double { parse(vinesPerHaText) }
    private var bunchWeightGrams: Double { parse(bunchWeightText) }

    private var budsPerVine: Double {
        switch pruneMethod {
        case .spur: return budsPerSpur * spursPerVine
        case .cane: return budsPerCane * canesPerVine
        }
    }

    private var bunchesPerHa: Double {
        bunchesPerBud * budsPerVine * vinesPerHa
    }

    private var yieldKgPerHa: Double {
        bunchesPerHa * bunchWeightGrams / 1000.0
    }

    private var yieldTonnesPerHa: Double {
        yieldKgPerHa / 1000.0
    }

    private var totalYieldTonnes: Double? {
        guard let paddock = selectedPaddock, paddock.areaHectares > 0 else { return nil }
        return yieldTonnesPerHa * paddock.areaHectares
    }

    private var formulaText: String {
        switch pruneMethod {
        case .spur:
            return "Yield / Ha = Bunches/Bud × Buds/Spur × Spurs/Vine × Vines/Ha × Bunch Weight"
        case .cane:
            return "Yield / Ha = Bunches/Bud × Buds/Cane × Canes/Vine × Vines/Ha × Bunch Weight"
        }
    }

    var body: some View {
        Form {
            Section("Paddock") {
                if vineyardPaddocks.isEmpty {
                    Text("No paddocks available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Paddock", selection: $selectedPaddockId) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(vineyardPaddocks) { paddock in
                            Text(paddock.name).tag(Optional(paddock.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let paddock = selectedPaddock {
                        LabeledContent("Area") {
                            Text(String(format: "%.2f ha", paddock.areaHectares))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Vines") {
                            Text("\(paddock.effectiveVineCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Pruning Method") {
                Picker("Method", selection: $pruneMethod) {
                    ForEach(PruneMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                Text(pruneMethod == .spur
                     ? "Spur pruning: short canes (spurs) left with a set number of buds each."
                     : "Cane pruning: longer canes retained on each vine with multiple buds per cane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Inputs") {
                inputRow(label: "Bunches / Bud", text: $bunchesPerBudText, field: .bunchesPerBud)

                switch pruneMethod {
                case .spur:
                    inputRow(label: "Buds / Spur", text: $budsPerSpurText, field: .budsPerSpur)
                    inputRow(label: "Spurs / Vine", text: $spursPerVineText, field: .spursPerVine)
                case .cane:
                    inputRow(label: "Buds / Cane", text: $budsPerCaneText, field: .budsPerCane)
                    inputRow(label: "Canes / Vine", text: $canesPerVineText, field: .canesPerVine)
                }

                inputRow(label: "Vines / Ha", text: $vinesPerHaText, field: .vinesPerHa)
                inputRow(label: "Bunch Weight (g)", text: $bunchWeightText, field: .bunchWeight)
            }

            Section("Calculated") {
                LabeledContent("Buds / Vine") {
                    Text(budsPerVine, format: .number.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                LabeledContent("Bunches / Ha") {
                    Text(bunchesPerHa, format: .number.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Yield")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.1f kg/ha", yieldKgPerHa))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(VineyardTheme.leafGreen)
                            .monospacedDigit()
                        Text(String(format: "%.1f t/ha", yieldTonnesPerHa))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)

                if let total = totalYieldTonnes {
                    LabeledContent("Block Total") {
                        Text(String(format: "%.1f t", total))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section {
                Text(formulaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Yield Determination")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear {
            if selectedPaddockId == nil {
                selectedPaddockId = vineyardPaddocks.first?.id
            }
            applyPaddockDefaults()
        }
        .onChange(of: selectedPaddockId) { _, _ in
            applyPaddockDefaults()
        }
    }

    private func inputRow(label: String, text: Binding<String>, field: Field) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .frame(maxWidth: 120)
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
                    if let textField = notification.object as? UITextField {
                        textField.selectAll(nil)
                    }
                }
        }
    }

    private func applyPaddockDefaults() {
        guard let paddock = selectedPaddock else { return }
        let area = paddock.areaHectares
        let vines = Double(paddock.effectiveVineCount)
        if area > 0, vines > 0 {
            let computed = vines / area
            vinesPerHaText = String(format: "%.0f", computed)
        }
    }

    private func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
