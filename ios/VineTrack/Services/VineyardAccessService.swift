import Foundation
import Supabase
import PostgREST

nonisolated struct VineyardAccessMemberRecord: Codable, Sendable {
    let vineyard_id: String
    let user_id: String
    let email: String?
    let display_name: String?
    let role: String
    let joined_at: String?
}

nonisolated struct VineyardAccessPayload: Codable, Sendable {
    let vineyards: [VineyardRecord]
    let members: [VineyardAccessMemberRecord]
    let pendingInvitations: [TeamInvitation]
    let vineyardData: [SyncRecord]
}

nonisolated enum VineyardAccessServiceError: LocalizedError, Sendable {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloud service is not configured."
        }
    }
}

struct VineyardAccessService {
    static func fetch() async throws -> VineyardAccessPayload {
        guard !Config.EXPO_PUBLIC_SUPABASE_URL.isEmpty,
              !Config.EXPO_PUBLIC_SUPABASE_ANON_KEY.isEmpty else {
            throw VineyardAccessServiceError.notConfigured
        }

        return try await supabase
            .rpc("get_vinetrack_access_snapshot")
            .execute()
            .value
    }
}
