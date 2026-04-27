import SwiftUI

@Observable
@MainActor
class AccessControl {
    private let store: DataStore
    private let authService: AuthService

    init(store: DataStore, authService: AuthService) {
        self.store = store
        self.authService = authService
    }

    /// Membership for the currently selected vineyard, sourced from the
    /// authoritative access snapshot. A user has a separate role per
    /// vineyard — there is no global role.
    var currentMembership: VineyardAccessMemberRecord? {
        guard let vid = store.selectedVineyardId else { return nil }
        return authService.membership(forVineyardId: vid)
    }

    /// Role for the currently selected vineyard, sourced from the access
    /// snapshot. Per-vineyard — there is no global role. Falls back to the
    /// local cached membership (offline) and finally Operator as a safe
    /// default (Step 13).
    var currentUserRole: VineyardRole {
        guard let vineyard = store.selectedVineyard else { return .operator_ }

        if let role = authService.role(forVineyardId: vineyard.id) {
            return role
        }

        guard let userId = authService.userId,
              let uuid = UUID(uuidString: userId) else {
            return .operator_
        }
        if let user = vineyard.users.first(where: { $0.id == uuid }) {
            return user.role
        }
        return .operator_
    }

    // MARK: - Permissions

    var canDelete: Bool { currentUserRole.canDelete }
    var canDeleteVineyard: Bool { currentUserRole.canDeleteVineyard }
    var canTransferOwnership: Bool { currentUserRole.canTransferOwnership }
    var canExport: Bool { currentUserRole.canExport }
    var canViewFinancials: Bool { currentUserRole.canViewFinancials }
    var canExportFinancialPDF: Bool { currentUserRole.canExportFinancialPDF }
    var canManageUsers: Bool { currentUserRole.canManageUsers }
    var canChangeSettings: Bool { currentUserRole.canChangeSettings }
    var canReopenRecords: Bool { currentUserRole.canReopenRecords }
    var canFinalizeRecords: Bool { currentUserRole.canFinalizeRecords }
    var isManager: Bool { currentUserRole.isManager }
    var isOperator: Bool { currentUserRole == .operator_ }

    /// Can this record be edited by the current user?
    /// Finalised records are read-only for Operators.
    func canEdit(isFinalized: Bool) -> Bool {
        if !isFinalized { return true }
        return canReopenRecords
    }

    /// Role for an arbitrary vineyard (not just the selected one). Used by
    /// list views that need per-row permissions. Falls back to local member
    /// data, then to Operator if no membership is known.
    func role(forVineyardId vineyardId: UUID) -> VineyardRole {
        if let role = authService.role(forVineyardId: vineyardId) {
            return role
        }
        guard let userId = authService.userId,
              let uuid = UUID(uuidString: userId),
              let vineyard = store.vineyards.first(where: { $0.id == vineyardId })
        else { return .operator_ }
        if let user = vineyard.users.first(where: { $0.id == uuid }) {
            return user.role
        }
        return .operator_
    }

    /// Whether the current user can delete the given vineyard. Only the
    /// Owner of that specific vineyard can delete it.
    func canDeleteVineyard(_ vineyard: Vineyard) -> Bool {
        role(forVineyardId: vineyard.id).canDeleteVineyard
    }

    /// Whether the current user can change another user's role in the
    /// currently selected vineyard.
    func canManage(role targetRole: VineyardRole) -> Bool {
        currentUserRole.canManage(role: targetRole)
    }
}

struct AccessControlKey: EnvironmentKey {
    static let defaultValue: AccessControl? = nil
}

extension EnvironmentValues {
    var accessControl: AccessControl? {
        get { self[AccessControlKey.self] }
        set { self[AccessControlKey.self] = newValue }
    }
}
