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
    var bunchCountEntry: BunchCountEntry?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isRecorded: Bool {
        bunchCountEntry != nil
    }

    init(
        id: UUID = UUID(),
        paddockId: UUID,
        paddockName: String = "",
        rowNumber: Int,
        latitude: Double,
        longitude: Double,
        siteIndex: Int,
        bunchCountEntry: BunchCountEntry? = nil
    ) {
        self.id = id
        self.paddockId = paddockId
        self.paddockName = paddockName
        self.rowNumber = rowNumber
        self.latitude = latitude
        self.longitude = longitude
        self.siteIndex = siteIndex
        self.bunchCountEntry = bunchCountEntry
    }
}

nonisolated struct BunchCountEntry: Codable, Sendable, Hashable {
    var bunchesPerVine: Double
    var recordedAt: Date
    var recordedBy: String

    init(
        bunchesPerVine: Double,
        recordedAt: Date = Date(),
        recordedBy: String = ""
    ) {
        self.bunchesPerVine = bunchesPerVine
        self.recordedAt = recordedAt
        self.recordedBy = recordedBy
    }
}

nonisolated struct YieldEstimationSession: Codable, Identifiable, Sendable {
    let id: UUID
    var vineyardId: UUID
    var createdAt: Date
    var selectedPaddockIds: [UUID]
    var samplesPerHectare: Int
    var sampleSites: [SampleSite]
    var averageBunchWeightKg: Double
    var previousBunchWeights: [BunchWeightRecord]
    var pathWaypoints: [CoordinatePoint]

    init(
        id: UUID = UUID(),
        vineyardId: UUID,
        createdAt: Date = Date(),
        selectedPaddockIds: [UUID] = [],
        samplesPerHectare: Int = 20,
        sampleSites: [SampleSite] = [],
        averageBunchWeightKg: Double = 0.15,
        previousBunchWeights: [BunchWeightRecord] = [],
        pathWaypoints: [CoordinatePoint] = []
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.createdAt = createdAt
        self.selectedPaddockIds = selectedPaddockIds
        self.samplesPerHectare = samplesPerHectare
        self.sampleSites = sampleSites
        self.averageBunchWeightKg = averageBunchWeightKg
        self.previousBunchWeights = previousBunchWeights
        self.pathWaypoints = pathWaypoints
    }
}

nonisolated struct BunchWeightRecord: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var date: Date
    var weightKg: Double

    init(id: UUID = UUID(), date: Date = Date(), weightKg: Double = 0.15) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
    }
}

nonisolated struct BlockYieldEstimate: Sendable {
    let paddockId: UUID
    let paddockName: String
    let areaHectares: Double
    let totalVines: Int
    let averageBunchesPerVine: Double
    let totalBunches: Double
    let averageBunchWeightKg: Double
    let damageFactor: Double
    let estimatedYieldKg: Double
    let estimatedYieldTonnes: Double
    let samplesRecorded: Int
    let samplesTotal: Int
}
