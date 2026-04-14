import Foundation

nonisolated struct HistoricalYieldRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var vineyardId: UUID
    var season: String
    var year: Int
    var archivedAt: Date
    var blockResults: [HistoricalBlockResult]
    var totalYieldTonnes: Double
    var totalAreaHectares: Double
    var notes: String

    var yieldPerHectare: Double {
        guard totalAreaHectares > 0 else { return 0 }
        return totalYieldTonnes / totalAreaHectares
    }

    init(
        id: UUID = UUID(),
        vineyardId: UUID,
        season: String = "",
        year: Int = Calendar.current.component(.year, from: Date()),
        archivedAt: Date = Date(),
        blockResults: [HistoricalBlockResult] = [],
        totalYieldTonnes: Double = 0,
        totalAreaHectares: Double = 0,
        notes: String = ""
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.season = season
        self.year = year
        self.archivedAt = archivedAt
        self.blockResults = blockResults
        self.totalYieldTonnes = totalYieldTonnes
        self.totalAreaHectares = totalAreaHectares
        self.notes = notes
    }
}

nonisolated struct HistoricalBlockResult: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var paddockId: UUID
    var paddockName: String
    var areaHectares: Double
    var yieldTonnes: Double
    var yieldPerHectare: Double
    var averageBunchesPerVine: Double
    var averageBunchWeightGrams: Double
    var totalVines: Int
    var samplesRecorded: Int
    var damageFactor: Double

    init(
        id: UUID = UUID(),
        paddockId: UUID,
        paddockName: String,
        areaHectares: Double = 0,
        yieldTonnes: Double = 0,
        yieldPerHectare: Double = 0,
        averageBunchesPerVine: Double = 0,
        averageBunchWeightGrams: Double = 0,
        totalVines: Int = 0,
        samplesRecorded: Int = 0,
        damageFactor: Double = 1.0
    ) {
        self.id = id
        self.paddockId = paddockId
        self.paddockName = paddockName
        self.areaHectares = areaHectares
        self.yieldTonnes = yieldTonnes
        self.yieldPerHectare = yieldPerHectare
        self.averageBunchesPerVine = averageBunchesPerVine
        self.averageBunchWeightGrams = averageBunchWeightGrams
        self.totalVines = totalVines
        self.samplesRecorded = samplesRecorded
        self.damageFactor = damageFactor
    }
}
