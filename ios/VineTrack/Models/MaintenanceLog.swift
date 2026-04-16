import Foundation

nonisolated struct MaintenanceLog: Codable, Identifiable, Sendable {
    var id: UUID
    var vineyardId: UUID
    var itemName: String
    var hours: Double
    var workCompleted: String
    var partsUsed: String
    var partsCost: Double
    var labourCost: Double
    var date: Date
    var invoicePhotoData: Data?
    var createdBy: String?

    init(
        id: UUID = UUID(),
        vineyardId: UUID = UUID(),
        itemName: String = "",
        hours: Double = 0,
        workCompleted: String = "",
        partsUsed: String = "",
        partsCost: Double = 0,
        labourCost: Double = 0,
        date: Date = Date(),
        invoicePhotoData: Data? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.itemName = itemName
        self.hours = hours
        self.workCompleted = workCompleted
        self.partsUsed = partsUsed
        self.partsCost = partsCost
        self.labourCost = labourCost
        self.date = date
        self.invoicePhotoData = invoicePhotoData
        self.createdBy = createdBy
    }

    var totalCost: Double { partsCost + labourCost }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, vineyardId, itemName, hours, workCompleted, partsUsed, partsCost, labourCost, date, invoicePhotoData, createdBy
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        vineyardId = try container.decode(UUID.self, forKey: .vineyardId)
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName) ?? ""
        hours = try container.decodeIfPresent(Double.self, forKey: .hours) ?? 0
        workCompleted = try container.decodeIfPresent(String.self, forKey: .workCompleted) ?? ""
        partsUsed = try container.decodeIfPresent(String.self, forKey: .partsUsed) ?? ""
        partsCost = try container.decodeIfPresent(Double.self, forKey: .partsCost) ?? 0
        labourCost = try container.decodeIfPresent(Double.self, forKey: .labourCost) ?? 0
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        invoicePhotoData = try container.decodeIfPresent(Data.self, forKey: .invoicePhotoData)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
    }
}
