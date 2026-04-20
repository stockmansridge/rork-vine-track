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
              let uuid = UUID(uuidString: userId),
              let user = vineyard.users.first(where: { $0.id == uuid }) else {
            if let user = vineyard.users.first(where: {
                $0.name.lowercased() == authService.userName.lowercased()
            }) {
                return user.role
            }
            if vineyard.users.count == 1, let only = vineyard.users.first {
                return only.role
            }
            return .operator_
        }
        return user.role
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
