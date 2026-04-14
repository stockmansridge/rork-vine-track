import Foundation

import SwiftUI

nonisolated enum AppAppearance: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

nonisolated struct AppSettings: Codable, Sendable, Identifiable {
    var id: UUID
    var vineyardId: UUID
    var timezone: String
    var seasonStartMonth: Int
    var seasonStartDay: Int
    var rowTrackingEnabled: Bool
    var rowTrackingInterval: Double
    var defaultPaddockId: UUID?
    var autoPhotoPrompt: Bool
    var enabledGrowthStageCodes: [String]
    var weatherStationId: String?
    var defaultWaterVolume: Double
    var defaultSprayRate: Double
    var defaultConcentrationFactor: Double
    var paddockOrder: [UUID]
    var canopyWaterRates: CanopyWaterRateEntry
    var seasonFuelCostPerLitre: Double
    var appearance: AppAppearance
    var fillTimerEnabled: Bool
    var samplesPerHectare: Int
    var defaultBlockBunchWeightsGrams: [UUID: Double]

    init(
        id: UUID = UUID(),
        vineyardId: UUID = UUID(),
        timezone: String = TimeZone.current.identifier,
        seasonStartMonth: Int = 7,
        seasonStartDay: Int = 1,
        rowTrackingEnabled: Bool = true,
        rowTrackingInterval: Double = 1.0,
        defaultPaddockId: UUID? = nil,
        autoPhotoPrompt: Bool = false,
        enabledGrowthStageCodes: [String] = GrowthStage.allStages.map { $0.code },
        weatherStationId: String? = nil,
        defaultWaterVolume: Double = 0,
        defaultSprayRate: Double = 0,
        defaultConcentrationFactor: Double = 1.0,
        paddockOrder: [UUID] = [],
        canopyWaterRates: CanopyWaterRateEntry = .defaults,
        seasonFuelCostPerLitre: Double = 0,
        appearance: AppAppearance = .system,
        fillTimerEnabled: Bool = false,
        samplesPerHectare: Int = 20,
        defaultBlockBunchWeightsGrams: [UUID: Double] = [:]
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.timezone = timezone
        self.seasonStartMonth = seasonStartMonth
        self.seasonStartDay = seasonStartDay
        self.rowTrackingEnabled = rowTrackingEnabled
        self.rowTrackingInterval = rowTrackingInterval
        self.defaultPaddockId = defaultPaddockId
        self.autoPhotoPrompt = autoPhotoPrompt
        self.enabledGrowthStageCodes = enabledGrowthStageCodes
        self.weatherStationId = weatherStationId
        self.defaultWaterVolume = defaultWaterVolume
        self.defaultSprayRate = defaultSprayRate
        self.defaultConcentrationFactor = defaultConcentrationFactor
        self.paddockOrder = paddockOrder
        self.canopyWaterRates = canopyWaterRates
        self.seasonFuelCostPerLitre = seasonFuelCostPerLitre
        self.appearance = appearance
        self.fillTimerEnabled = fillTimerEnabled
        self.samplesPerHectare = samplesPerHectare
        self.defaultBlockBunchWeightsGrams = defaultBlockBunchWeightsGrams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        vineyardId = try container.decode(UUID.self, forKey: .vineyardId)
        timezone = try container.decode(String.self, forKey: .timezone)
        seasonStartMonth = try container.decode(Int.self, forKey: .seasonStartMonth)
        seasonStartDay = try container.decode(Int.self, forKey: .seasonStartDay)
        rowTrackingEnabled = try container.decode(Bool.self, forKey: .rowTrackingEnabled)
        rowTrackingInterval = try container.decode(Double.self, forKey: .rowTrackingInterval)
        defaultPaddockId = try container.decodeIfPresent(UUID.self, forKey: .defaultPaddockId)
        autoPhotoPrompt = try container.decodeIfPresent(Bool.self, forKey: .autoPhotoPrompt) ?? false
        enabledGrowthStageCodes = try container.decode([String].self, forKey: .enabledGrowthStageCodes)
        weatherStationId = try container.decodeIfPresent(String.self, forKey: .weatherStationId)
        defaultWaterVolume = try container.decodeIfPresent(Double.self, forKey: .defaultWaterVolume) ?? 0
        defaultSprayRate = try container.decodeIfPresent(Double.self, forKey: .defaultSprayRate) ?? 0
        defaultConcentrationFactor = try container.decodeIfPresent(Double.self, forKey: .defaultConcentrationFactor) ?? 1.0
        paddockOrder = try container.decodeIfPresent([UUID].self, forKey: .paddockOrder) ?? []
        canopyWaterRates = try container.decodeIfPresent(CanopyWaterRateEntry.self, forKey: .canopyWaterRates) ?? .defaults
        seasonFuelCostPerLitre = try container.decodeIfPresent(Double.self, forKey: .seasonFuelCostPerLitre) ?? 0
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        fillTimerEnabled = try container.decodeIfPresent(Bool.self, forKey: .fillTimerEnabled) ?? false
        samplesPerHectare = try container.decodeIfPresent(Int.self, forKey: .samplesPerHectare) ?? 20
        defaultBlockBunchWeightsGrams = try container.decodeIfPresent([UUID: Double].self, forKey: .defaultBlockBunchWeightsGrams) ?? [:]
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, vineyardId, timezone, seasonStartMonth, seasonStartDay
        case rowTrackingEnabled, rowTrackingInterval, defaultPaddockId
        case autoPhotoPrompt, enabledGrowthStageCodes, weatherStationId
        case defaultWaterVolume, defaultSprayRate, defaultConcentrationFactor
        case paddockOrder, canopyWaterRates, seasonFuelCostPerLitre, appearance, fillTimerEnabled, samplesPerHectare, defaultBlockBunchWeightsGrams
    }
}
