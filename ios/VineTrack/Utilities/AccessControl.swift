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

    var canDelete: Bool { currentUserRole.canDelete }
    var canExport: Bool { currentUserRole.canExport }
    var isManager: Bool { currentUserRole == .owner || currentUserRole == .manager }
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
