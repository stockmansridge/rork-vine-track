import Testing
import Foundation
@testable import VineTrack

@MainActor
struct AccessControlTests {

    private func makeStore(withRole role: VineyardRole, userId: UUID = UUID(), userName: String = "User") -> (DataStore, AuthService, AccessControl, UUID) {
        let store = DataStore()
        let vineyard = Vineyard(
            name: "AC \(UUID().uuidString.prefix(6))",
            users: [VineyardUser(id: userId, name: userName, role: role)]
        )
        store.addVineyard(vineyard)
        store.selectedVineyardId = vineyard.id

        let auth = AuthService()
        auth.userId = userId.uuidString
        auth.userName = userName

        let ac = AccessControl(store: store, authService: auth)
        store.accessControl = ac
        return (store, auth, ac, vineyard.id)
    }

    // MARK: - Role resolution

    @Test func ownerHasFullAccess() {
        let (_, _, ac, _) = makeStore(withRole: .owner)
        #expect(ac.currentUserRole == .owner)
        #expect(ac.canDelete)
        #expect(ac.canExport)
        #expect(ac.canViewFinancials)
        #expect(ac.canExportFinancialPDF)
        #expect(ac.canManageUsers)
        #expect(ac.canChangeSettings)
        #expect(ac.canReopenRecords)
        #expect(ac.canFinalizeRecords)
        #expect(ac.isManager)
        #expect(!ac.isOperator)
    }

    @Test func managerHasFullAccess() {
        let (_, _, ac, _) = makeStore(withRole: .manager)
        #expect(ac.currentUserRole == .manager)
        #expect(ac.canViewFinancials)
        #expect(ac.canExportFinancialPDF)
        #expect(ac.canManageUsers)
        #expect(ac.canChangeSettings)
        #expect(ac.isManager)
    }

    @Test func supervisorCanDeleteAndExportButNotFinancials() {
        let (_, _, ac, _) = makeStore(withRole: .supervisor)
        #expect(ac.currentUserRole == .supervisor)
        #expect(ac.canDelete)
        #expect(ac.canExport)
        #expect(!ac.canViewFinancials)
        #expect(!ac.canExportFinancialPDF)
        #expect(!ac.canManageUsers)
        #expect(!ac.canChangeSettings)
        #expect(ac.canReopenRecords)
        #expect(ac.canFinalizeRecords)
        #expect(!ac.isManager)
    }

    @Test func operatorCannotDoAnythingSensitive() {
        let (_, _, ac, _) = makeStore(withRole: .operator_)
        #expect(ac.isOperator)
        #expect(!ac.canDelete)
        #expect(!ac.canExport)
        #expect(!ac.canViewFinancials)
        #expect(!ac.canExportFinancialPDF)
        #expect(!ac.canManageUsers)
        #expect(!ac.canChangeSettings)
        #expect(!ac.canReopenRecords)
        #expect(!ac.canFinalizeRecords)
        #expect(!ac.isManager)
    }

    // MARK: - Identity fallbacks

    @Test func defaultsToOperatorWhenNoVineyardSelected() {
        let store = DataStore()
        let auth = AuthService()
        let ac = AccessControl(store: store, authService: auth)
        #expect(ac.currentUserRole == .operator_)
        #expect(!ac.canDelete)
        #expect(!ac.canChangeSettings)
    }

    @Test func defaultsToOperatorWhenIdentityMissing() {
        let store = DataStore()
        let vineyard = Vineyard(
            name: "NoMatch",
            users: [
                VineyardUser(id: UUID(), name: "Alice", role: .manager),
                VineyardUser(id: UUID(), name: "Bob", role: .supervisor)
            ]
        )
        store.addVineyard(vineyard)
        store.selectedVineyardId = vineyard.id

        let auth = AuthService()
        auth.userId = nil
        auth.userName = "Unknown"
        let ac = AccessControl(store: store, authService: auth)
        // Multiple users, no identity match → fails closed to operator.
        #expect(ac.currentUserRole == .operator_)
    }

    @Test func nameMatchesWhenUUIDMissing() {
        let store = DataStore()
        let vineyard = Vineyard(
            name: "NameMatch",
            users: [VineyardUser(id: UUID(), name: "Charlie", role: .manager)]
        )
        store.addVineyard(vineyard)
        store.selectedVineyardId = vineyard.id

        let auth = AuthService()
        auth.userId = nil
        auth.userName = "charlie" // case-insensitive
        let ac = AccessControl(store: store, authService: auth)
        #expect(ac.currentUserRole == .manager)
    }

    @Test func singleUserFallback() {
        let store = DataStore()
        let vineyard = Vineyard(
            name: "Solo",
            users: [VineyardUser(id: UUID(), name: "Owner", role: .owner)]
        )
        store.addVineyard(vineyard)
        store.selectedVineyardId = vineyard.id

        // No matching identity at all → single user fallback picks that user.
        let auth = AuthService()
        auth.userId = UUID().uuidString
        auth.userName = "Someone Else"
        let ac = AccessControl(store: store, authService: auth)
        #expect(ac.currentUserRole == .owner)
    }

    // MARK: - canEdit(isFinalized:)

    @Test func canEditOpenRecordAlways() {
        let (_, _, ac, _) = makeStore(withRole: .operator_)
        #expect(ac.canEdit(isFinalized: false))
    }

    @Test func operatorCannotEditFinalized() {
        let (_, _, ac, _) = makeStore(withRole: .operator_)
        #expect(!ac.canEdit(isFinalized: true))
    }

    @Test func supervisorCanEditFinalized() {
        let (_, _, ac, _) = makeStore(withRole: .supervisor)
        #expect(ac.canEdit(isFinalized: true))
    }

    @Test func managerCanEditFinalized() {
        let (_, _, ac, _) = makeStore(withRole: .manager)
        #expect(ac.canEdit(isFinalized: true))
    }
}
