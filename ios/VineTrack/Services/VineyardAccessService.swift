import Foundation
import Supabase
import PostgREST

nonisolated struct VineyardAccessUserRecord: Codable, Sendable {
    let id: String
    let email: String?
    let name: String?
}

nonisolated struct VineyardAccessMemberRecord: Codable, Sendable {
    let vineyard_id: String
    let user_id: String
    let email: String?
    let display_name: String?
    let role: String
    let joined_at: String?
}

nonisolated struct VineyardAccessPayload: Codable, Sendable {
    let user: VineyardAccessUserRecord?
    let vineyards: [VineyardRecord]
    let memberships: [VineyardAccessMemberRecord]
    let pendingInvitations: [TeamInvitation]
    let vineyardData: [SyncRecord]

    enum CodingKeys: String, CodingKey {
        case user
        case vineyards
        case memberships
        case members
        case pendingInvitations
        case vineyardData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.user = try c.decodeIfPresent(VineyardAccessUserRecord.self, forKey: .user)
        self.vineyards = try c.decodeIfPresent([VineyardRecord].self, forKey: .vineyards) ?? []
        // Accept either `memberships` (new RPC) or `members` (legacy RPC).
        if let m = try c.decodeIfPresent([VineyardAccessMemberRecord].self, forKey: .memberships) {
            self.memberships = m
        } else {
            self.memberships = try c.decodeIfPresent([VineyardAccessMemberRecord].self, forKey: .members) ?? []
        }
        self.pendingInvitations = try c.decodeIfPresent([TeamInvitation].self, forKey: .pendingInvitations) ?? []
        self.vineyardData = try c.decodeIfPresent([SyncRecord].self, forKey: .vineyardData) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(user, forKey: .user)
        try c.encode(vineyards, forKey: .vineyards)
        try c.encode(memberships, forKey: .memberships)
        try c.encode(pendingInvitations, forKey: .pendingInvitations)
        try c.encode(vineyardData, forKey: .vineyardData)
    }
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

/// Single source of truth for the signed-in user's access state.
///
/// After authentication, the app calls `AccessService.loadAccessSnapshot()`
/// (aliased as `VineyardAccessService.fetch()` for backwards compatibility).
/// The snapshot returns the user, every accessible vineyard, the user's
/// role in each vineyard, and pending invitations in a single round-trip.
///
/// The app trusts this response — it does NOT chain multiple fallback
/// queries (owner_id lookups, same-email claims, synthesized rows). If
/// the user is missing access, fix it on the backend, not by guessing
/// in the client.
struct VineyardAccessService {
    static func fetch() async throws -> VineyardAccessPayload {
        guard !Config.EXPO_PUBLIC_SUPABASE_URL.isEmpty,
              !Config.EXPO_PUBLIC_SUPABASE_ANON_KEY.isEmpty else {
            throw VineyardAccessServiceError.notConfigured
        }

        return try await supabase
            .rpc("get_my_access_snapshot")
            .execute()
            .value
    }
}

typealias AccessService = VineyardAccessService
