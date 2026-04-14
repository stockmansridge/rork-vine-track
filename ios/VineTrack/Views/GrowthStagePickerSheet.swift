import SwiftUI

struct GrowthStagePickerSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    let onSelect: (GrowthStage) -> Void

    private var enabledStages: [GrowthStage] {
        let enabledCodes = store.settings.enabledGrowthStageCodes
        return GrowthStage.allStages.filter { enabledCodes.contains($0.code) }
    }

    private var filteredStages: [GrowthStage] {
        guard !searchText.isEmpty else { return enabledStages }
        return enabledStages.filter {
            $0.code.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredStages) { stage in
                    Button {
                        onSelect(stage)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(stage.code)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 32)
                                .background(Color.green.gradient, in: .rect(cornerRadius: 6))

                            Text(stage.description)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        .contentShape(.rect)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search stages")
            .navigationTitle("Select Growth Stage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
