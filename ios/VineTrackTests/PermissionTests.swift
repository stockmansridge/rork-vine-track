import Testing
import Foundation
@testable import VineTrack

struct PermissionTests {

    @Test func operatorPermissions() {
        let role: VineyardRole = .operator_
        #expect(role.canDelete == false)
        #expect(role.canExport == false)
        #expect(role.canViewFinancials == false)
        #expect(role.canExportFinancialPDF == false)
        #expect(role.canManageUsers == false)
        #expect(role.canChangeSettings == false)
        #expect(role.canReopenRecords == false)
        #expect(role.canFinalizeRecords == false)
        #expect(role.isManager == false)
    }

    @Test func supervisorPermissions() {
        let role: VineyardRole = .supervisor
        #expect(role.canDelete == true)
        #expect(role.canExport == true)
        #expect(role.canViewFinancials == false)
        #expect(role.canExportFinancialPDF == false)
        #expect(role.canManageUsers == false)
        #expect(role.canChangeSettings == false)
        #expect(role.canReopenRecords == true)
        #expect(role.canFinalizeRecords == true)
        #expect(role.isManager == false)
    }

    @Test func managerPermissions() {
        let role: VineyardRole = .manager
        #expect(role.canDelete == true)
        #expect(role.canExport == true)
        #expect(role.canViewFinancials == true)
        #expect(role.canExportFinancialPDF == true)
        #expect(role.canManageUsers == true)
        #expect(role.canChangeSettings == true)
        #expect(role.canReopenRecords == true)
        #expect(role.canFinalizeRecords == true)
        #expect(role.isManager == true)
    }

    @Test func ownerPermissions() {
        let role: VineyardRole = .owner
        #expect(role.canDelete == true)
        #expect(role.canExport == true)
        #expect(role.canViewFinancials == true)
        #expect(role.canExportFinancialPDF == true)
        #expect(role.canManageUsers == true)
        #expect(role.canChangeSettings == true)
        #expect(role.isManager == true)
    }

    @Test func legacyMemberDecodesAsOperator() throws {
        // Legacy data stored "Member" for the operator role.
        let json = "\"Member\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VineyardRole.self, from: json)
        #expect(decoded == .operator_)
    }

    @Test func rolesRoundtripJSON() throws {
        for role in VineyardRole.allCases {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(VineyardRole.self, from: data)
            #expect(decoded == role)
        }
    }
}
