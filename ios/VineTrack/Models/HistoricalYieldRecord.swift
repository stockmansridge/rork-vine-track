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

    var totalActualYieldTonnes: Double? {
        let actuals = blockResults.compactMap { $0.actualYieldTonnes }
        guard !actuals.isEmpty else { return nil }
        return actuals.reduce(0, +)
    }

    var actualYieldPerHectare: Double? {
        guard let total = totalActualYieldTonnes, totalAreaHectares > 0 else { return nil }
        return total / totalAreaHectares
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
    var actualYieldTonnes: Double?
    var actualRecordedAt: Date?

    var actualYieldPerHectare: Double? {
        guard let actual = actualYieldTonnes, areaHectares > 0 else { return nil }
        return actual / areaHectares
    }

    var yieldVarianceTonnes: Double? {
        guard let actual = actualYieldTonnes else { return nil }
        return actual - yieldTonnes
    }

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
        damageFactor: Double = 1.0,
        actualYieldTonnes: Double? = nil,
        actualRecordedAt: Date? = nil
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
        self.actualYieldTonnes = actualYieldTonnes
        self.actualRecordedAt = actualRecordedAt
    }
}
