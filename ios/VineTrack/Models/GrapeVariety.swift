import Foundation

nonisolated struct GrapeVariety: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var vineyardId: UUID
    var name: String
    var optimalGDD: Double
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        vineyardId: UUID = UUID(),
        name: String,
        optimalGDD: Double,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.name = name
        self.optimalGDD = optimalGDD
        self.isBuiltIn = isBuiltIn
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, vineyardId, name, optimalGDD, isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        vineyardId = try c.decode(UUID.self, forKey: .vineyardId)
        name = try c.decode(String.self, forKey: .name)
        optimalGDD = try c.decode(Double.self, forKey: .optimalGDD)
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }
}

extension GrapeVariety {
    static func defaults(for vineyardId: UUID) -> [GrapeVariety] {
        // Optimal growing degree days (base 10°C) to harvest ripeness.
        // Values are typical ranges from viticulture references.
        let data: [(String, Double)] = [
            ("Chardonnay", 1250),
            ("Pinot Noir", 1150),
            ("Pinot Gris", 1200),
            ("Sauvignon Blanc", 1300),
            ("Riesling", 1200),
            ("Gruner Veltliner", 1300),
            ("Merlot", 1450),
            ("Cabernet Franc", 1500),
            ("Cabernet Sauvignon", 1650),
            ("Shiraz", 1550),
            ("Syrah", 1550),
            ("Tempranillo", 1500),
            ("Sangiovese", 1550),
            ("Nebbiolo", 1700),
            ("Zinfandel", 1600),
            ("Primitivo", 1600),
            ("Malbec", 1500),
            ("Grenache", 1700),
            ("Mourvedre", 1800),
            ("Viognier", 1400),
            ("Semillon", 1350),
            ("Muscat", 1350),
            ("Chenin Blanc", 1350),
            ("Gewurztraminer", 1250),
            ("Barbera", 1550),
            ("Montepulciano", 1600)
        ]
        return data.map { GrapeVariety(vineyardId: vineyardId, name: $0.0, optimalGDD: $0.1, isBuiltIn: true) }
    }
}

nonisolated struct PaddockVarietyAllocation: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var varietyId: UUID
    var percent: Double

    init(id: UUID = UUID(), varietyId: UUID, percent: Double) {
        self.id = id
        self.varietyId = varietyId
        self.percent = percent
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, varietyId, percent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        varietyId = try c.decode(UUID.self, forKey: .varietyId)
        percent = try c.decode(Double.self, forKey: .percent)
    }
}
