import SwiftUI

struct BlockImportView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let importData: BlockExportData

    @State private var replaceExisting: Bool = false
    @State private var didImport: Bool = false
    @State private var importedCount: Int = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Source Vineyard", value: importData.vineyardName)
                    LabeledContent("Exported", value: importData.exportDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Blocks", value: "\(importData.paddocks.count)")
                } header: {
                    Text("Import File")
                }

                Section {
                    ForEach(importData.paddocks) { paddock in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paddock.name)
                                .font(.headline)
                            HStack(spacing: 12) {
                                Label("\(paddock.rows.count) rows", systemImage: "line.3.horizontal")
                                Label("\(paddock.polygonPoints.count) pts", systemImage: "mappin.and.ellipse")
                                if paddock.areaHectares > 0 {
                                    Label(String(format: "%.2f ha", paddock.areaHectares), systemImage: "square.dashed")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Blocks to Import")
                }

                Section {
                    Toggle("Replace Existing Blocks", isOn: $replaceExisting)
                } footer: {
                    if replaceExisting {
                        Text("All existing blocks in the current vineyard will be removed and replaced with the imported blocks.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Only blocks with new names will be added. Existing blocks with the same name will be skipped.")
                    }
                }
            }
            .navigationTitle("Import Blocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importedCount = BlockExportImportService.importBlocks(
                            from: importData,
                            into: store,
                            replaceExisting: replaceExisting
                        )
                        didImport = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Import Complete", isPresented: $didImport) {
                Button("Done") { dismiss() }
            } message: {
                Text("\(importedCount) block\(importedCount == 1 ? "" : "s") imported successfully.")
            }
        }
    }
}
