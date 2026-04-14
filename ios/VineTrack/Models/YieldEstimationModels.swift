import Foundation
import CoreLocation

nonisolated struct SampleSite: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var paddockId: UUID
    var paddockName: String
    var rowNumber: Int
    var latitude: Double
    var longitude: Double
    var siteIndex: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        paddockId: UUID,
        paddockName: String = "",
        rowNumber: Int,
        latitude: Double,
        longitude: Double,
        siteIndex: Int
    ) {
        self.id = id
        self.paddockId = paddockId
        self.paddockName = paddockName
        self.rowNumber = rowNumber
        self.latitude = latitude
        self.longitude = longitude
        self.siteIndex = siteIndex
    }
}

nonisolated struct YieldEstimationSession: Codable, Identifiable, Sendable {
    let id: UUID
    var vineyardId: UUID
    var createdAt: Date
    var selectedPaddockIds: [UUID]
    var samplesPerHectare: Int
    var sampleSites: [SampleSite]

    init(
        id: UUID = UUID(),
        vineyardId: UUID,
        createdAt: Date = Date(),
        selectedPaddockIds: [UUID] = [],
        samplesPerHectare: Int = 20,
        sampleSites: [SampleSite] = []
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.createdAt = createdAt
        self.selectedPaddockIds = selectedPaddockIds
        self.samplesPerHectare = samplesPerHectare
        self.sampleSites = sampleSites
    }
}
