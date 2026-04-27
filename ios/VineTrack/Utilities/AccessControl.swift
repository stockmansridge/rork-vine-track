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

    var currentUserRole: VineyardRole {
        guard let vineyard = store.selectedVineyard else { return .operator_ }
        guard let userId = authService.userId,
              let uuid = UUID(uuidString: userId) else {
            return .operator_
        }
        if let user = vineyard.users.first(where: { $0.id == uuid }) {
            return user.role
        }
        // Email match is a safe secondary lookup (the signed-in user's own
        // email cannot belong to another member). Name-based or "only user"
        // fallbacks are intentionally removed: with stale local data they
        // can hand the current user the previous user's role.
        let email = authService.userEmail.lowercased()
        if !email.isEmpty,
           let user = vineyard.users.first(where: { $0.email.lowercased() == email }) {
            return user.role
        }
        return .operator_
    }

    // MARK: - Permissions

    var canDelete: Bool { currentUserRole.canDelete }
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
