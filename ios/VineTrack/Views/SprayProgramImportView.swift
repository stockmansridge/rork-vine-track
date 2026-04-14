import SwiftUI

struct SprayProgramImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    let importedRows: [SprayProgramCSVService.ImportedSprayRow]
    let warnings: [SprayProgramCSVService.ImportWarning]

    @State private var importedCount: Int?
    @State private var isImporting: Bool = false
    @State private var showAllWarnings: Bool = false

    private var criticalWarnings: [SprayProgramCSVService.ImportWarning] {
        warnings.filter { w in
            w.message.contains("skipped") || w.message.contains("example row") || w.message.contains("invalid")
        }
    }

    private var infoWarnings: [SprayProgramCSVService.ImportWarning] {
        warnings.filter { w in
            !w.message.contains("skipped") && !w.message.contains("example row") && !w.message.contains("invalid")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "tablecells.badge.ellipsis")
                            .font(.title2)
                            .foregroundStyle(VineyardTheme.olive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(importedRows.count) spray record\(importedRows.count == 1 ? "" : "s") found")
                                .font(.headline)
                            Text("Review the records below before importing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !criticalWarnings.isEmpty {
                    Section {
                        ForEach(Array(criticalWarnings.enumerated()), id: \.offset) { _, warning in
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Row \(warning.row)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(warning.message)
                                        .font(.caption)
                                }
                            }
                        }
                    } header: {
                        Label("Issues", systemImage: "exclamationmark.triangle")
                    }
                }

                if !infoWarnings.isEmpty {
                    Section {
                        let displayWarnings = showAllWarnings ? infoWarnings : Array(infoWarnings.prefix(5))
                        ForEach(Array(displayWarnings.enumerated()), id: \.offset) { _, warning in
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Row \(warning.row)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(warning.message)
                                        .font(.caption)
                                }
                            }
                        }
                        if infoWarnings.count > 5 && !showAllWarnings {
                            Button {
                                showAllWarnings = true
                            } label: {
                                Text("Show all \(infoWarnings.count) warnings")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    } header: {
                        Label("Warnings (\(infoWarnings.count))", systemImage: "exclamationmark.circle")
                    }
                }

                Section("Preview") {
                    ForEach(Array(importedRows.enumerated()), id: \.offset) { index, row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.sprayName.isEmpty ? "Untitled Spray" : row.sprayName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(row.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !row.blockName.isEmpty {
                                Label { Text(row.blockName) } icon: { GrapeLeafIcon(size: 12) }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !row.chemicals.isEmpty {
                                Text(row.chemicals.map(\.name).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            HStack(spacing: 12) {
                                if row.waterVolume > 0 {
                                    Label("\(String(format: "%.0f", row.waterVolume))L", systemImage: "drop")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                if !row.equipment.isEmpty {
                                    Label(row.equipment, systemImage: "wrench.and.screwdriver")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                if !row.operatorName.isEmpty {
                                    Label(row.operatorName, systemImage: "person")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let importedCount {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Successfully imported \(importedCount) record\(importedCount == 1 ? "" : "s")")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
            .navigationTitle("Import Spray Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importedCount != nil ? "Done" : "Cancel") {
                        dismiss()
                    }
                }

                if importedCount == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            performImport()
                        } label: {
                            if isImporting {
                                ProgressView()
                            } else {
                                Text("Import")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isImporting)
                    }
                }
            }
        }
    }

    private func performImport() {
        isImporting = true
        let count = SprayProgramCSVService.importRows(
            importedRows,
            into: store,
            paddocks: store.paddocks
        )
        importedCount = count
        isImporting = false
    }
}
