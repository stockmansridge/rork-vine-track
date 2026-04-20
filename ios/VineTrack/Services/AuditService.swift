import Foundation
import Supabase

@Observable
@MainActor
class AuditService {
    private(set) var entries: [AuditLogEntry] = []

    private let key = "vinetrack_audit_log"
    private weak var store: DataStore?
    private weak var authService: AuthService?
    private weak var accessControl: AccessControl?

    private static let storageDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("VineTrackData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        load()
    }

    func configure(store: DataStore, authService: AuthService, accessControl: AccessControl?) {
        self.store = store
        self.authService = authService
        self.accessControl = accessControl
    }

    func entries(for vineyardId: UUID) -> [AuditLogEntry] {
        entries.filter { $0.vineyardId == vineyardId }.sorted { $0.timestamp > $1.timestamp }
    }

    func log(
        action: AuditAction,
        entityType: String,
        entityId: String? = nil,
        entityLabel: String = "",
        details: String = ""
    ) {
        guard let vineyardId = store?.selectedVineyardId else { return }
        let userName = authService?.userName ?? ""
        let userId = authService?.userId
        let role = accessControl?.currentUserRole.rawValue ?? ""
        let entry = AuditLogEntry(
            vineyardId: vineyardId,
            userId: userId,
            userName: userName,
            userRole: role,
            action: action,
            entityType: entityType,
            entityId: entityId,
            entityLabel: entityLabel,
            details: details
        )
        entries.insert(entry, at: 0)
        if entries.count > 5000 {
            entries = Array(entries.prefix(5000))
        }
        save()
        Task { await pushToCloud(entry) }
    }

    private func load() {
        let fileURL = Self.storageDirectory.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([AuditLogEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        let fileURL = Self.storageDirectory.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func pushToCloud(_ entry: AuditLogEntry) async {
        guard isSupabaseConfigured else { return }
        struct Row: Encodable, Sendable {
            let id: String
            let vineyard_id: String
            let user_id: String?
            let user_name: String
            let user_role: String
            let action: String
            let entity_type: String
            let entity_id: String?
            let entity_label: String
            let details: String
            let created_at: String
        }
        let row = Row(
            id: entry.id.uuidString,
            vineyard_id: entry.vineyardId.uuidString,
            user_id: entry.userId,
            user_name: entry.userName,
            user_role: entry.userRole,
            action: entry.action.rawValue,
            entity_type: entry.entityType,
            entity_id: entry.entityId,
            entity_label: entry.entityLabel,
            details: entry.details,
            created_at: ISO8601DateFormatter().string(from: entry.timestamp)
        )
        do {
            try await supabase.from("audit_logs").insert(row).execute()
        } catch {
            print("AuditService: Failed to push audit entry: \(error.localizedDescription)")
        }
    }
}
