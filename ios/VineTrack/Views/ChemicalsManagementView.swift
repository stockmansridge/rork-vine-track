import SwiftUI

struct ChemicalsManagementView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.accessControl) private var accessControl
    @State private var showAddSheet: Bool = false
    @State private var editingChemical: SavedChemical?
    @State private var searchText: String = ""

    private var filteredChemicals: [SavedChemical] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return store.savedChemicals
        }
        return store.savedChemicals.filter { chem in
            let combined = "\(chem.name) \(chem.activeIngredient) \(chem.chemicalGroup) \(chem.manufacturer) \(chem.problem) \(chem.modeOfAction)"
            return combined.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filteredChemicals) { chemical in
                Button {
                    editingChemical = chemical
                } label: {
                    ChemicalDetailRow(chemical: chemical)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if accessControl?.canDelete ?? false {
                        Button(role: .destructive) {
                            store.deleteSavedChemical(chemical)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chemicals")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search chemicals...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if store.savedChemicals.isEmpty {
                ContentUnavailableView {
                    Label("No Chemicals", systemImage: "flask")
                } description: {
                    Text("Add chemicals to quickly select them in spray records.")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            EditSavedChemicalSheet(chemical: nil)
        }
        .sheet(item: $editingChemical) { chem in
            EditSavedChemicalSheet(chemical: chem)
        }
    }
}

struct ChemicalDetailRow: View {
    let chemical: SavedChemical

    private var ratesPerHa: [ChemicalRate] {
        chemical.rates.filter { $0.basis == .perHectare }
    }

    private var ratesPer100L: [ChemicalRate] {
        chemical.rates.filter { $0.basis == .per100Litres }
    }

    private var tags: [(String, Color)] {
        var result: [(String, Color)] = []
        if !chemical.unit.rawValue.isEmpty {
            result.append((chemical.unit.rawValue, .brown))
        }
        if !chemical.chemicalGroup.isEmpty {
            result.append((chemical.chemicalGroup, VineyardTheme.olive))
        }
        if !chemical.problem.isEmpty {
            result.append((chemical.problem, .blue))
        }
        if !chemical.modeOfAction.isEmpty {
            result.append(("MOA: \(chemical.modeOfAction)", .orange))
        }
        return result
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(chemical.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                if !tags.isEmpty {
                    WrappingHStack(spacing: 6, lineSpacing: 4) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                            Text(tag.0)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(tag.1.opacity(0.12))
                                .foregroundStyle(tag.1)
                                .clipShape(Capsule())
                        }
                    }
                }

                if !ratesPerHa.isEmpty {
                    Text(ratesPerHa.map { "\($0.label): \(String(format: "%.0f", chemical.unit.fromBase($0.value)))/ha" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !ratesPer100L.isEmpty {
                    Text(ratesPer100L.map { "\($0.label): \(String(format: "%.0f", chemical.unit.fromBase($0.value)))/100L" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if ratesPerHa.isEmpty && ratesPer100L.isEmpty && chemical.ratePerHa > 0 {
                    Text("\(String(format: "%.2f", chemical.ratePerHa)) L/Kg per Ha")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !chemical.activeIngredient.isEmpty {
                    Text(chemical.activeIngredient)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if !chemical.manufacturer.isEmpty {
                    Text(chemical.manufacturer)
                        .font(.caption2)
                        .foregroundStyle(VineyardTheme.olive)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct WrappingHStack: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
