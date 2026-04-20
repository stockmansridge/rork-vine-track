import SwiftUI

struct AuditLogView: View {
    @Environment(DataStore.self) private var store
    @Environment(AuditService.self) private var auditService
    @Environment(\.accessControl) private var accessControl

    @State private var filterAction: AuditAction?

    private var entries: [AuditLogEntry] {
        guard let vid = store.selectedVineyardId else { return [] }
        var items = auditService.entries(for: vid)
        if let action = filterAction {
            items = items.filter { $0.action == action }
        }
        return items
    }

    var body: some View {
        Group {
            if accessControl?.isManager ?? false {
                listContent
            } else {
                restrictedView
            }
        }
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var restrictedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Manager Only")
                .font(.title3.weight(.semibold))
            Text("Only Managers can view the audit log.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var listContent: some View {
        List {
            Section {
                Menu {
                    Button("All Actions") { filterAction = nil }
                    Divider()
                    ForEach(AuditAction.allCases, id: \.self) { action in
                        Button(action.displayName) { filterAction = action }
                    }
                } label: {
                    HStack {
                        Label(filterAction?.displayName ?? "All Actions", systemImage: "line.3.horizontal.decrease.circle")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if entries.isEmpty {
                Section {
                    Text("No audit entries yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Recent Activity") {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ entry: AuditLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(entry.action.displayName, systemImage: icon(for: entry.action))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: entry.action))
                Spacer()
                Text(entry.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(entry.entityType)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if !entry.entityLabel.isEmpty {
                    Text("— \(entry.entityLabel)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            if !entry.details.isEmpty {
                Text(entry.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(entry.userName.isEmpty ? "Unknown" : entry.userName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !entry.userRole.isEmpty {
                    Text("· \(entry.userRole)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func icon(for action: AuditAction) -> String {
        switch action {
        case .delete: return "trash.fill"
        case .softDelete: return "archivebox.fill"
        case .restore: return "arrow.uturn.backward.circle.fill"
        case .settingsChanged: return "gearshape.fill"
        case .roleChanged: return "person.badge.key.fill"
        case .userAdded: return "person.fill.badge.plus"
        case .userRemoved: return "person.fill.badge.minus"
        case .financialExport: return "dollarsign.square.fill"
        case .recordFinalized: return "lock.fill"
        case .recordReopened: return "lock.open.fill"
        }
    }

    private func color(for action: AuditAction) -> Color {
        switch action {
        case .delete: return .red
        case .softDelete: return .orange
        case .restore: return .green
        case .settingsChanged: return .blue
        case .roleChanged: return .purple
        case .userAdded: return .green
        case .userRemoved: return .red
        case .financialExport: return VineyardTheme.leafGreen
        case .recordFinalized: return .orange
        case .recordReopened: return .teal
        }
    }
}
