import Foundation
import Supabase
import Realtime

nonisolated struct SyncRecord: Codable, Sendable {
    let id: String
    let vineyard_id: String
    let data_type: String
    let data: String
    let updated_at: String
}

nonisolated struct VineyardRecord: Codable, Sendable {
    let id: String
    let name: String
    let owner_id: String?
    let logo_data: String?
    let created_at: String?
    let country: String?
}

nonisolated struct VineyardMemberRecord: Codable, Sendable {
    let id: String?
    let vineyard_id: String
    let user_id: String
    let name: String
    let role: String
    let joined_at: String?
}

nonisolated struct MemberWithEmailRow: Codable, Sendable {
    let user_id: String
    let email: String
    let display_name: String
    let role: String
    let joined_at: String?
}

nonisolated struct ELStageImageManifestEntry: Codable, Sendable, Equatable {
    let code: String
    let updated_at: String
}

nonisolated struct ELStageImageManifest: Codable, Sendable {
    let entries: [ELStageImageManifestEntry]
}

nonisolated enum SyncStatus: Sendable {
    case idle
    case syncing
    case synced
    case error(String)
}

@Observable
@MainActor
class CloudSyncService {
    var syncStatus: SyncStatus = .idle
    var lastSyncDate: Date?
    /// Becomes `true` after the first `pullAllData` call has completed for the
    /// current sign-in (success or failure). Used by `ContentView` so we don't
    /// flash the "Welcome / Create vineyard" screen while the cloud is still
    /// being queried for vineyards the user already owns or is a member of.
    var hasCompletedInitialSync: Bool = false

    func resetInitialSyncFlag() {
        hasCompletedInitialSync = false
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var realtimeChannel: RealtimeChannelV2?
    private var subscriptions: [RealtimeSubscription] = []
    private weak var boundStore: DataStore?
    private var subscribedVineyardIds: Set<String> = []

    var isConfigured: Bool {
        isSupabaseConfigured
    }

    /// Choose the best human-readable name for a vineyard member row.
    /// - If the RPC returned a real display_name (different from the email), use it.
    /// - Otherwise humanise the email's local-part (e.g. "john.doe@foo.com" -> "John Doe").
    /// - Otherwise fall back to the email, or an empty string.
    nonisolated static func preferredName(displayName: String, email: String) -> String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty && trimmedName.lowercased() != trimmedEmail.lowercased() {
            return trimmedName
        }
        guard !trimmedEmail.isEmpty, let atIndex = trimmedEmail.firstIndex(of: "@") else {
            return trimmedName
        }
        let local = String(trimmedEmail[..<atIndex])
        let parts = local
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")
            .split(separator: ".")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        let humanised = parts.joined(separator: " ")
        return humanised.isEmpty ? trimmedEmail : humanised
    }

    private var currentUserId: String? {
        supabase.auth.currentUser?.id.uuidString.lowercased()
    }

    private let syncTimestampsKey = "vinetrack_sync_timestamps"

    private func localTimestamp(for vineyardId: UUID, dataType: String) -> Date? {
        let dict = UserDefaults.standard.dictionary(forKey: syncTimestampsKey) as? [String: String] ?? [:]
        let key = "\(vineyardId.uuidString)_\(dataType)"
        guard let str = dict[key] else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    private func setLocalTimestamp(_ date: Date, for vineyardId: UUID, dataType: String) {
        var dict = UserDefaults.standard.dictionary(forKey: syncTimestampsKey) as? [String: String] ?? [:]
        let key = "\(vineyardId.uuidString)_\(dataType)"
        dict[key] = ISO8601DateFormatter().string(from: date)
        UserDefaults.standard.set(dict, forKey: syncTimestampsKey)
    }

    // MARK: - Real-time Subscriptions

    func startRealtime(for store: DataStore) async {
        guard isConfigured, currentUserId != nil else { return }
        boundStore = store

        await stopRealtime()

        let channel = supabase.channel("vineyard-data-changes")

        let sub1 = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "vineyard_data"
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleVineyardDataChange(action)
            }
        }
        subscriptions.append(sub1)

        let sub2 = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "vineyards"
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleVineyardChange(action)
            }
        }
        subscriptions.append(sub2)

        realtimeChannel = channel
        await channel.subscribe()
    }

    func stopRealtime() async {
        subscriptions.removeAll()
        if let channel = realtimeChannel {
            await supabase.removeChannel(channel)
            realtimeChannel = nil
        }
        subscribedVineyardIds.removeAll()
    }

    private func handleVineyardDataChange(_ action: AnyAction) {
        guard let store = boundStore else { return }

        var vineyardIdStr: String?
        var dataType: String?

        switch action {
        case .insert(let insertAction):
            vineyardIdStr = insertAction.record["vineyard_id"]?.stringValue
            dataType = insertAction.record["data_type"]?.stringValue
        case .update(let updateAction):
            vineyardIdStr = updateAction.record["vineyard_id"]?.stringValue
            dataType = updateAction.record["data_type"]?.stringValue
        case .delete:
            Task { await pullAllData(for: store) }
            return
        }

        guard let vidStr = vineyardIdStr,
              let vineyardId = UUID(uuidString: vidStr),
              let dt = dataType else { return }

        Task {
            await pullDataType(dt, for: vineyardId, store: store)
        }
    }

    private func handleVineyardChange(_ action: AnyAction) {
        guard let store = boundStore else { return }
        Task { await pullAllData(for: store) }
    }

    private func pullDataType(_ dataType: String, for vineyardId: UUID, store: DataStore) async {
        guard isConfigured else { return }
        do {
            let records: [SyncRecord] = try await supabase.from("vineyard_data")
                .select()
                .eq("vineyard_id", value: vineyardId.uuidString)
                .eq("data_type", value: dataType)
                .execute()
                .value

            for record in records {
                guard let jsonData = record.data.data(using: .utf8) else { continue }
                let remoteDate = ISO8601DateFormatter().date(from: record.updated_at) ?? Date.distantPast
                let localDate = localTimestamp(for: vineyardId, dataType: dataType)

                if localDate == nil || remoteDate > localDate! {
                    try mergeRecord(record.data_type, jsonData: jsonData, vineyardId: vineyardId, store: store, replace: true)
                    setLocalTimestamp(remoteDate, for: vineyardId, dataType: dataType)
                }
            }
            store.reloadCurrentVineyardData()
        } catch {
            print("CloudSync: Failed to pull \(dataType): \(error)")
        }
    }

    /// Claims access to any vineyards owned by - or shared with - another
    /// auth.users row that has the same email as the current user. Handles
    /// the case where a user originally signed up with email/password and
    /// later signs in via Google or Apple, which Supabase treats as a
    /// separate auth identity. Backed by the SECURITY DEFINER RPC
    /// `claim_vineyards_by_email`.
    func claimVineyardsByEmail() async {
        guard isConfigured, currentUserId != nil else { return }
        do {
            try await supabase.rpc("claim_vineyards_by_email").execute()
            print("CloudSync: claim_vineyards_by_email RPC executed")
        } catch {
            print("CloudSync: claim_vineyards_by_email RPC failed (run sql/claim_vineyards_by_email.sql in Supabase): \(error)")
        }
    }

    // MARK: - Full Sync

    func syncAllData(from store: DataStore) async {
        guard isConfigured, currentUserId != nil else { return }
        syncStatus = .syncing

        do {
            for vineyard in store.vineyards {
                try await uploadVineyard(vineyard)
            }

            let allData: [(String, UUID, any Encodable & Sendable)] = gatherSyncData(from: store)
            let now = Date()
            for (dataType, vineyardId, data) in allData {
                let jsonData = try encoder.encode(AnyEncodableWrapper(data))
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                let timestamp = ISO8601DateFormatter().string(from: now)
                let record = SyncRecord(
                    id: "\(vineyardId.uuidString)_\(dataType)",
                    vineyard_id: vineyardId.uuidString,
                    data_type: dataType,
                    data: jsonString,
                    updated_at: timestamp
                )
                try await supabase.from("vineyard_data")
                    .upsert(record)
                    .execute()
                setLocalTimestamp(now, for: vineyardId, dataType: dataType)
            }

            syncStatus = .synced
            lastSyncDate = Date()
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    func pullAllData(for store: DataStore) async {
        guard isConfigured, let userId = currentUserId else {
            hasCompletedInitialSync = true
            return
        }
        syncStatus = .syncing
        defer { hasCompletedInitialSync = true }

        do {
            nonisolated struct VineyardIdRow: Codable, Sendable {
                let vineyard_id: String
            }

            var idSet = Set<String>()
            // Vineyard records pre-fetched via SECURITY DEFINER RPC so we
            // don't depend on the per-row RLS SELECT on `vineyards` for the
            // current auth identity. This is critical on shared devices /
            // fresh Google sign-ins where the just-inserted vineyard_members
            // row hasn't yet propagated for the new uid.
            var prefetchedRecords: [String: VineyardRecord] = [:]

            if let rows: [VineyardRecord] = try? await supabase
                .rpc("get_my_vineyards_full")
                .execute()
                .value {
                for r in rows {
                    let key = r.id.lowercased()
                    idSet.insert(key)
                    prefetchedRecords[key] = r
                }
            } else {
                print("CloudSync: get_my_vineyards_full RPC not available, falling back (run sql/get_my_vineyards_full.sql in Supabase)")
            }

            // Fallback: server-side RPC that aggregates owner /
            // membership / same-email matches and auto-heals missing
            // vineyard_members rows for the current uid.
            if let rows: [VineyardIdRow] = try? await supabase
                .rpc("get_my_vineyard_ids")
                .execute()
                .value {
                for r in rows { idSet.insert(r.vineyard_id.lowercased()) }
            } else {
                print("CloudSync: get_my_vineyard_ids RPC not available, using fallback (run sql/get_my_vineyard_ids.sql in Supabase)")
            }

            let myMemberships: [VineyardMemberRecord] = (try? await supabase.from("vineyard_members")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value) ?? []

            let ownedVineyards: [VineyardRecord] = (try? await supabase.from("vineyards")
                .select()
                .eq("owner_id", value: userId)
                .execute()
                .value) ?? []

            for m in myMemberships { idSet.insert(m.vineyard_id.lowercased()) }
            for v in ownedVineyards {
                idSet.insert(v.id.lowercased())
                prefetchedRecords[v.id.lowercased()] = v
            }
            let vineyardIds = Array(idSet)

            for owned in ownedVineyards where !myMemberships.contains(where: { $0.vineyard_id.lowercased() == owned.id.lowercased() }) {
                let memberRecord = VineyardMemberRecord(
                    id: nil,
                    vineyard_id: owned.id,
                    user_id: userId,
                    name: supabase.auth.currentUser?.email ?? "",
                    role: VineyardRole.owner.rawValue,
                    joined_at: nil
                )
                _ = try? await supabase.from("vineyard_members")
                    .upsert(memberRecord, onConflict: "vineyard_id,user_id")
                    .execute()
            }

            guard !vineyardIds.isEmpty else {
                syncStatus = .synced
                lastSyncDate = Date()
                return
            }

            var vineyards: [Vineyard] = []
            for vid in vineyardIds {
                let record: VineyardRecord?
                if let pre = prefetchedRecords[vid] {
                    record = pre
                } else {
                    let records: [VineyardRecord] = (try? await supabase.from("vineyards")
                        .select()
                        .eq("id", value: vid)
                        .execute()
                        .value) ?? []
                    record = records.first
                }

                if let record {
                    nonisolated struct RPCParams: Codable, Sendable {
                        let p_vineyard_id: String
                    }
                    let rpcParams = RPCParams(p_vineyard_id: vid.lowercased())
                    var users: [VineyardUser] = []
                    if let rows: [MemberWithEmailRow] = try? await supabase.rpc(
                        "get_vineyard_members_with_email",
                        params: rpcParams
                    ).execute().value {
                        users = rows.map { r in
                            VineyardUser(
                                id: UUID(uuidString: r.user_id) ?? UUID(),
                                name: Self.preferredName(displayName: r.display_name, email: r.email),
                                email: r.email,
                                role: VineyardRole(rawValue: r.role) ?? .operator_
                            )
                        }
                    } else {
                        let allMembers: [VineyardMemberRecord] = (try? await supabase.from("vineyard_members")
                            .select()
                            .eq("vineyard_id", value: vid)
                            .execute()
                            .value) ?? []
                        users = allMembers.map { m in
                            VineyardUser(
                                id: UUID(uuidString: m.user_id) ?? UUID(),
                                name: m.name,
                                email: "",
                                role: VineyardRole(rawValue: m.role) ?? .operator_
                            )
                        }
                    }
                    var logoData: Data?
                    if let logoBase64 = record.logo_data {
                        logoData = Data(base64Encoded: logoBase64)
                    }
                    let vineyard = Vineyard(
                        id: UUID(uuidString: record.id) ?? UUID(),
                        name: record.name,
                        users: users,
                        createdAt: ISO8601DateFormatter().date(from: record.created_at ?? "") ?? Date(),
                        logoData: logoData,
                        country: record.country ?? ""
                    )
                    vineyards.append(vineyard)
                }
            }

            if !vineyards.isEmpty {
                store.mergeVineyards(vineyards)
            } else if !vineyardIds.isEmpty {
                print("CloudSync: \(vineyardIds.count) vineyard ids returned but no vineyard records could be loaded - check RLS / run sql/get_my_vineyards_full.sql")
            }

            for vid in vineyardIds {
                let dataRecords: [SyncRecord] = try await supabase.from("vineyard_data")
                    .select()
                    .eq("vineyard_id", value: vid)
                    .execute()
                    .value

                guard let vineyardUUID = UUID(uuidString: vid) else { continue }

                for record in dataRecords {
                    guard let jsonData = record.data.data(using: .utf8) else { continue }
                    let remoteDate = ISO8601DateFormatter().date(from: record.updated_at) ?? Date.distantPast
                    let localDate = localTimestamp(for: vineyardUUID, dataType: record.data_type)

                    if localDate == nil || remoteDate > localDate! {
                        try mergeRecord(record.data_type, jsonData: jsonData, vineyardId: vineyardUUID, store: store, replace: true)
                        setLocalTimestamp(remoteDate, for: vineyardUUID, dataType: record.data_type)
                    }
                }
            }

            store.reloadCurrentVineyardData()
            syncStatus = .synced
            lastSyncDate = Date()
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    /// Refresh just the members list for a specific vineyard from Supabase
    /// and update the local vineyard record. Used by the Team & Access screen
    /// so newly-accepted invitations appear without a full re-sync.
    ///
    /// Uses the SECURITY DEFINER RPC `get_vineyard_members_with_email` which
    /// reliably returns every member joined with their auth email, bypassing
    /// RLS quirks and empty profile names that previously caused blank rows.
    func refreshMembers(for vineyardId: UUID, store: DataStore) async {
        guard isConfigured else { return }

        nonisolated struct RPCParams: Codable, Sendable {
            let p_vineyard_id: String
        }
        let params = RPCParams(p_vineyard_id: vineyardId.uuidString.lowercased())

        var users: [VineyardUser] = []

        do {
            let rows: [MemberWithEmailRow] = try await supabase.rpc(
                "get_vineyard_members_with_email",
                params: params
            )
            .execute()
            .value

            users = rows.map { r in
                VineyardUser(
                    id: UUID(uuidString: r.user_id) ?? UUID(),
                    name: Self.preferredName(displayName: r.display_name, email: r.email),
                    email: r.email,
                    role: VineyardRole(rawValue: r.role) ?? .operator_
                )
            }
        } catch {
            print("CloudSync: get_vineyard_members_with_email RPC failed, falling back to direct query: \(error)")

            let members: [VineyardMemberRecord] = (try? await supabase.from("vineyard_members")
                .select()
                .eq("vineyard_id", value: vineyardId.uuidString)
                .execute()
                .value) ?? []

            users = members.map { m in
                VineyardUser(
                    id: UUID(uuidString: m.user_id) ?? UUID(),
                    name: m.name,
                    email: "",
                    role: VineyardRole(rawValue: m.role) ?? .operator_
                )
            }
        }

        guard var vineyard = store.vineyards.first(where: { $0.id == vineyardId }) else { return }

        // Preserve the operatorCategoryId we already have locally, since the
        // RPC only returns membership info, not the local-only operator
        // category assignment.
        let existingCategories = Dictionary(uniqueKeysWithValues: vineyard.users.map { ($0.id, $0.operatorCategoryId) })
        for i in users.indices {
            if let catId = existingCategories[users[i].id] {
                users[i].operatorCategoryId = catId
            }
        }

        vineyard.users = users
        store.updateVineyardUsers(vineyard)
    }

    /// Update a member's role in the vineyard_members table. Called from the
    /// Edit Access sheet so the role change actually takes effect (not just
    /// locally). Silent no-op if Supabase is not configured.
    func updateMemberRole(vineyardId: UUID, userId: UUID, role: VineyardRole) async {
        guard isConfigured else { return }
        nonisolated struct RoleUpdate: Codable, Sendable {
            let role: String
        }
        do {
            try await supabase.from("vineyard_members")
                .update(RoleUpdate(role: role.rawValue))
                .eq("vineyard_id", value: vineyardId.uuidString.lowercased())
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
        } catch {
            print("CloudSync: Failed to update member role: \(error)")
        }
    }

    /// Remove a member from a vineyard in the vineyard_members table.
    func removeMember(vineyardId: UUID, userId: UUID) async {
        guard isConfigured else { return }
        do {
            try await supabase.from("vineyard_members")
                .delete()
                .eq("vineyard_id", value: vineyardId.uuidString.lowercased())
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
        } catch {
            print("CloudSync: Failed to remove member: \(error)")
        }
    }

    func uploadVineyard(_ vineyard: Vineyard) async throws {
        guard isConfigured, let userId = currentUserId else { return }

        let logoBase64 = vineyard.logoData?.base64EncodedString()
        let record = VineyardRecord(
            id: vineyard.id.uuidString,
            name: vineyard.name,
            owner_id: userId,
            logo_data: logoBase64,
            created_at: ISO8601DateFormatter().string(from: vineyard.createdAt),
            country: vineyard.country.isEmpty ? nil : vineyard.country
        )
        try await supabase.from("vineyards")
            .upsert(record)
            .execute()

        let memberRecord = VineyardMemberRecord(
            id: nil,
            vineyard_id: vineyard.id.uuidString,
            user_id: userId,
            name: supabase.auth.currentUser?.email ?? "",
            role: VineyardRole.owner.rawValue,
            joined_at: nil
        )
        try await supabase.from("vineyard_members")
            .upsert(memberRecord, onConflict: "vineyard_id,user_id")
            .execute()
    }

    func uploadDataForVineyard(_ vineyardId: UUID, dataType: String, data: any Encodable & Sendable) async {
        guard isConfigured, currentUserId != nil else { return }
        do {
            let jsonData = try encoder.encode(AnyEncodableWrapper(data))
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            let now = Date()
            let timestamp = ISO8601DateFormatter().string(from: now)
            let record = SyncRecord(
                id: "\(vineyardId.uuidString)_\(dataType)",
                vineyard_id: vineyardId.uuidString,
                data_type: dataType,
                data: jsonString,
                updated_at: timestamp
            )
            try await supabase.from("vineyard_data")
                .upsert(record)
                .execute()
            setLocalTimestamp(now, for: vineyardId, dataType: dataType)
        } catch {
            print("CloudSync: Failed to upload \(dataType): \(error)")
        }
    }

    // MARK: - Storage (vineyard assets)

    private let assetsBucket = "vineyard-assets"

    func uploadELStageImage(_ data: Data, vineyardId: UUID, code: String) async throws {
        guard isConfigured else { return }
        let path = "\(vineyardId.uuidString)/el-stage-images/\(code).jpg"
        _ = try await supabase.storage.from(assetsBucket).upload(
            path,
            data: data,
            options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
        )
    }

    func downloadELStageImage(vineyardId: UUID, code: String) async throws -> Data {
        let path = "\(vineyardId.uuidString)/el-stage-images/\(code).jpg"
        return try await supabase.storage.from(assetsBucket).download(path: path)
    }

    func removeELStageImage(vineyardId: UUID, code: String) async {
        guard isConfigured else { return }
        let path = "\(vineyardId.uuidString)/el-stage-images/\(code).jpg"
        _ = try? await supabase.storage.from(assetsBucket).remove(paths: [path])
    }

    func deleteVineyardFromCloud(_ vineyardId: UUID) async {
        guard isConfigured else { return }
        do {
            try await supabase.from("vineyard_data")
                .delete()
                .eq("vineyard_id", value: vineyardId.uuidString)
                .execute()
            try await supabase.from("vineyard_members")
                .delete()
                .eq("vineyard_id", value: vineyardId.uuidString)
                .execute()
            try await supabase.from("vineyards")
                .delete()
                .eq("id", value: vineyardId.uuidString)
                .execute()
        } catch {
            print("CloudSync: Failed to delete vineyard: \(error)")
        }
    }

    private func gatherSyncData(from store: DataStore) -> [(String, UUID, any Encodable & Sendable)] {
        var result: [(String, UUID, any Encodable & Sendable)] = []
        for vineyard in store.vineyards {
            let vid = vineyard.id
            let vinePins = store.allPins.filter { $0.vineyardId == vid }
            let paddocks = store.allPaddocks.filter { $0.vineyardId == vid }
            let trips = store.allTrips.filter { $0.vineyardId == vid }
            let repairBtns = store.allRepairButtons.filter { $0.vineyardId == vid }
            let growthBtns = store.allGrowthButtons.filter { $0.vineyardId == vid }
            let settings = store.allSettings.filter { $0.vineyardId == vid }
            let patterns = store.allCustomPatterns.filter { $0.vineyardId == vid }
            let sprayRecords = store.allSprayRecords.filter { $0.vineyardId == vid }
            let chemicals = store.allSavedChemicals.filter { $0.vineyardId == vid }
            let sprayPresets = store.allSavedSprayPresets.filter { $0.vineyardId == vid }
            let equipmentOptions = store.allSavedEquipmentOptions.filter { $0.vineyardId == vid }

            result.append(("pins", vid, vinePins))
            result.append(("paddocks", vid, paddocks))
            result.append(("trips", vid, trips))
            result.append(("repair_buttons", vid, repairBtns))
            result.append(("growth_buttons", vid, growthBtns))
            result.append(("settings", vid, settings))
            result.append(("custom_patterns", vid, patterns))
            result.append(("spray_records", vid, sprayRecords))
            result.append(("saved_chemicals", vid, chemicals))
            result.append(("saved_spray_presets", vid, sprayPresets))
            result.append(("saved_equipment_options", vid, equipmentOptions))

            let sprayEquip = store.allSprayEquipment.filter { $0.vineyardId == vid }
            let tractorItems = store.allTractors.filter { $0.vineyardId == vid }
            let fuelItems = store.allFuelPurchases.filter { $0.vineyardId == vid }
            result.append(("spray_equipment", vid, sprayEquip))
            result.append(("tractors", vid, tractorItems))
            result.append(("fuel_purchases", vid, fuelItems))

            let yieldSessions = store.yieldSessions.filter { $0.vineyardId == vid }
            let damageRecords = store.damageRecords.filter { $0.vineyardId == vid }
            let historicalYield = store.historicalYieldRecords.filter { $0.vineyardId == vid }
            let maintenanceLogs = store.maintenanceLogs.filter { $0.vineyardId == vid }
            let workTasks = store.workTasks.filter { $0.vineyardId == vid }
            result.append(("yield_sessions", vid, yieldSessions))
            result.append(("damage_records", vid, damageRecords))
            result.append(("historical_yield_records", vid, historicalYield))
            result.append(("maintenance_logs", vid, maintenanceLogs))
            result.append(("work_tasks", vid, workTasks))

            let operatorCategories = store.allOperatorCategories.filter { $0.vineyardId == vid }
            let buttonTemplates = store.allButtonTemplates.filter { $0.vineyardId == vid }
            let grapeVars = store.allGrapeVarieties.filter { $0.vineyardId == vid }
            result.append(("operator_categories", vid, operatorCategories))
            result.append(("button_templates", vid, buttonTemplates))
            result.append(("grape_varieties", vid, grapeVars))

            let manifest = store.elStageImageManifest(for: vid)
            result.append(("el_stage_images_manifest", vid, manifest))
        }
        return result
    }

    private func mergeRecord(_ dataType: String, jsonData: Data, vineyardId: UUID, store: DataStore, replace: Bool = false) throws {
        switch dataType {
        case "pins":
            let items = try decoder.decode([VinePin].self, from: jsonData)
            if replace {
                store.replacePins(items, for: vineyardId)
            } else {
                store.mergePins(items, for: vineyardId)
            }
        case "paddocks":
            let items = try decoder.decode([Paddock].self, from: jsonData)
            if replace {
                store.replacePaddocks(items, for: vineyardId)
            } else {
                store.mergePaddocks(items, for: vineyardId)
            }
        case "trips":
            let items = try decoder.decode([Trip].self, from: jsonData)
            if replace {
                store.replaceTrips(items, for: vineyardId)
            } else {
                store.mergeTrips(items, for: vineyardId)
            }
        case "repair_buttons":
            let items = try decoder.decode([ButtonConfig].self, from: jsonData)
            store.mergeRepairButtons(items, for: vineyardId)
        case "growth_buttons":
            let items = try decoder.decode([ButtonConfig].self, from: jsonData)
            store.mergeGrowthButtons(items, for: vineyardId)
        case "settings":
            let items = try decoder.decode([AppSettings].self, from: jsonData)
            store.mergeSettings(items, for: vineyardId)
        case "custom_patterns":
            let items = try decoder.decode([SavedCustomPattern].self, from: jsonData)
            if replace {
                store.replaceCustomPatterns(items, for: vineyardId)
            } else {
                store.mergeCustomPatterns(items, for: vineyardId)
            }
        case "spray_records":
            let items = try decoder.decode([SprayRecord].self, from: jsonData)
            if replace {
                store.replaceSprayRecords(items, for: vineyardId)
            } else {
                store.mergeSprayRecords(items, for: vineyardId)
            }
        case "saved_chemicals":
            let items = try decoder.decode([SavedChemical].self, from: jsonData)
            if replace {
                store.replaceSavedChemicals(items, for: vineyardId)
            } else {
                store.mergeSavedChemicals(items, for: vineyardId)
            }
        case "saved_spray_presets":
            let items = try decoder.decode([SavedSprayPreset].self, from: jsonData)
            if replace {
                store.replaceSavedSprayPresets(items, for: vineyardId)
            } else {
                store.mergeSavedSprayPresets(items, for: vineyardId)
            }
        case "saved_equipment_options":
            let items = try decoder.decode([SavedEquipmentOption].self, from: jsonData)
            if replace {
                store.replaceSavedEquipmentOptions(items, for: vineyardId)
            } else {
                store.mergeSavedEquipmentOptions(items, for: vineyardId)
            }
        case "spray_equipment":
            let items = try decoder.decode([SprayEquipmentItem].self, from: jsonData)
            if replace {
                store.replaceSprayEquipment(items, for: vineyardId)
            } else {
                store.mergeSprayEquipment(items, for: vineyardId)
            }
        case "tractors":
            let items = try decoder.decode([Tractor].self, from: jsonData)
            if replace {
                store.replaceTractors(items, for: vineyardId)
            } else {
                store.mergeTractors(items, for: vineyardId)
            }
        case "fuel_purchases":
            let items = try decoder.decode([FuelPurchase].self, from: jsonData)
            if replace {
                store.replaceFuelPurchases(items, for: vineyardId)
            } else {
                store.mergeFuelPurchases(items, for: vineyardId)
            }
        case "yield_sessions":
            let items = try decoder.decode([YieldEstimationSession].self, from: jsonData)
            if replace {
                store.replaceYieldSessions(items, for: vineyardId)
            } else {
                store.mergeYieldSessions(items, for: vineyardId)
            }
        case "damage_records":
            let items = try decoder.decode([DamageRecord].self, from: jsonData)
            if replace {
                store.replaceDamageRecords(items, for: vineyardId)
            } else {
                store.mergeDamageRecords(items, for: vineyardId)
            }
        case "historical_yield_records":
            let items = try decoder.decode([HistoricalYieldRecord].self, from: jsonData)
            if replace {
                store.replaceHistoricalYieldRecords(items, for: vineyardId)
            } else {
                store.mergeHistoricalYieldRecords(items, for: vineyardId)
            }
        case "maintenance_logs":
            let items = try decoder.decode([MaintenanceLog].self, from: jsonData)
            if replace {
                store.replaceMaintenanceLogs(items, for: vineyardId)
            } else {
                store.mergeMaintenanceLogs(items, for: vineyardId)
            }
        case "work_tasks":
            let items = try decoder.decode([WorkTask].self, from: jsonData)
            if replace {
                store.replaceWorkTasks(items, for: vineyardId)
            } else {
                store.mergeWorkTasks(items, for: vineyardId)
            }
        case "operator_categories":
            let items = try decoder.decode([OperatorCategory].self, from: jsonData)
            if replace {
                store.replaceOperatorCategories(items, for: vineyardId)
            } else {
                store.mergeOperatorCategories(items, for: vineyardId)
            }
        case "button_templates":
            let items = try decoder.decode([ButtonTemplate].self, from: jsonData)
            if replace {
                store.replaceButtonTemplates(items, for: vineyardId)
            } else {
                store.mergeButtonTemplates(items, for: vineyardId)
            }
        case "grape_varieties":
            let items = try decoder.decode([GrapeVariety].self, from: jsonData)
            if replace {
                store.replaceGrapeVarieties(items, for: vineyardId)
            } else {
                store.mergeGrapeVarieties(items, for: vineyardId)
            }
        case "el_stage_images_manifest":
            let manifest = try decoder.decode(ELStageImageManifest.self, from: jsonData)
            store.applyELStageImageManifest(manifest, for: vineyardId, using: self)
        default:
            break
        }
    }
}

nonisolated struct AnyEncodableWrapper: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init(_ wrapped: any Encodable & Sendable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
