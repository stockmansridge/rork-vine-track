import Foundation

nonisolated struct Vineyard: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var users: [VineyardUser]
    let createdAt: Date
    var logoData: Data?
    var country: String

    init(
        id: UUID = UUID(),
        name: String = "",
        users: [VineyardUser] = [],
        createdAt: Date = Date(),
        logoData: Data? = nil,
        country: String = ""
    ) {
        self.id = id
        self.name = name
        self.users = users
        self.createdAt = createdAt
        self.logoData = logoData
        self.country = country
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, name, users, createdAt, logoData, country
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        users = try container.decodeIfPresent([VineyardUser].self, forKey: .users) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        logoData = try container.decodeIfPresent(Data.self, forKey: .logoData)
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
    }
}

nonisolated struct VineyardUser: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var role: VineyardRole
    var operatorCategoryId: UUID?

    init(
        id: UUID = UUID(),
        name: String = "",
        role: VineyardRole = .member,
        operatorCategoryId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.operatorCategoryId = operatorCategoryId
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, name, role, operatorCategoryId
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try container.decodeIfPresent(VineyardRole.self, forKey: .role) ?? .member
        operatorCategoryId = try container.decodeIfPresent(UUID.self, forKey: .operatorCategoryId)
    }
}

nonisolated enum VineyardRole: String, Codable, Sendable, Hashable, CaseIterable {
    case owner = "Owner"
    case manager = "Manager"
    case member = "Member"
}
