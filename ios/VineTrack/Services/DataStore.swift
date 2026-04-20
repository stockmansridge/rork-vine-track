import Foundation
import CoreLocation
import UIKit

@Observable
@MainActor
class DataStore {
    var vineyards: [Vineyard] = []
    var selectedVineyardId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedVineyardId?.uuidString, forKey: selectedVineyardIdKey)
            loadVineyardData()
        }
    }

    var pins: [VinePin] = []
    var paddocks: [Paddock] = []
    var trips: [Trip] = []
    var repairButtons: [ButtonConfig] = []
    var growthButtons: [ButtonConfig] = []
    var settings: AppSettings = AppSettings()
    var savedCustomPatterns: [SavedCustomPattern] = []
    var sprayRecords: [SprayRecord] = []
    var savedChemicals: [SavedChemical] = []
    var savedSprayPresets: [SavedSprayPreset] = []
    var savedEquipmentOptions: [SavedEquipmentOption] = []
    var sprayEquipment: [SprayEquipmentItem] = []
    var tractors: [Tractor] = []
    var fuelPurchases: [FuelPurchase] = []
    var operatorCategories: [OperatorCategory] = []
    var buttonTemplates: [ButtonTemplate] = []
    var yieldSessions: [YieldEstimationSession] = []
    var damageRecords: [DamageRecord] = []
    var historicalYieldRecords: [HistoricalYieldRecord] = []
    var maintenanceLogs: [MaintenanceLog] = []
    var workTasks: [WorkTask] = []
    var grapeVarieties: [GrapeVariety] = []

    var selectedTab: Int = 0
    var cloudSync: CloudSyncService?
    var analytics: AnalyticsService?
    weak var auditService: AuditService?
    weak var authService: AuthService?
    weak var accessControl: AccessControl?

    // MARK: - Repositories (Phase 1)
    // Owns persistence + merge/replace logic for their domain.
    // DataStore delegates file I/O here instead of doing it inline.
    let workTaskRepository: WorkTaskRepository = WorkTaskRepository()
    let maintenanceLogRepository: MaintenanceLogRepository = MaintenanceLogRepository()

    // MARK: - Permission Guards

    private func assertCanDelete(_ label: String) -> Bool {
        guard let ac = accessControl else { return true }
        if !ac.canDelete {
            #if DEBUG
            print("⛔️ Permission denied: delete '\(label)' — role: \(ac.currentUserRole.rawValue)")
            #endif
            return false
        }
        return true
    }

    private func assertCanChangeSettings(_ label: String) -> Bool {
        guard let ac = accessControl else { return true }
        if !ac.canChangeSettings {
            #if DEBUG
            print("⛔️ Permission denied: change settings '\(label)' — role: \(ac.currentUserRole.rawValue)")
            #endif
            return false
        }
        return true
    }

    private func assertCanEdit(isFinalized: Bool, _ label: String) -> Bool {
        guard let ac = accessControl else { return true }
        if isFinalized && !ac.canReopenRecords {
            #if DEBUG
            print("⛔️ Permission denied: edit finalised '\(label)' — role: \(ac.currentUserRole.rawValue)")
            #endif
            return false
        }
        return true
    }

    let vineyardsKey = "vinetrack_vineyards"
    let selectedVineyardIdKey = "vinetrack_selected_vineyard_id"
    let pinsKey = "vinetrack_pins"
    let paddocksKey = "vinetrack_paddocks"
    let tripsKey = "vinetrack_trips"
    let repairButtonsKey = "vinetrack_repair_buttons"
    let growthButtonsKey = "vinetrack_growth_buttons"
    let settingsKey = "vinetrack_settings_v2"
    let customPatternsKey = "vinetrack_custom_patterns"
    let sprayRecordsKey = "vinetrack_spray_records"
    let savedChemicalsKey = "vinetrack_saved_chemicals"
    let savedSprayPresetsKey = "vinetrack_saved_spray_presets"
    let savedEquipmentOptionsKey = "vinetrack_saved_equipment_options"
    let sprayEquipmentKey = "vinetrack_spray_equipment"
    let tractorsKey = "vinetrack_tractors"
    let fuelPurchasesKey = "vinetrack_fuel_purchases"
    let operatorCategoriesKey = "vinetrack_operator_categories"
    let buttonTemplatesKey = "vinetrack_button_templates"
    let yieldSessionsKey = "vinetrack_yield_sessions"
    let damageRecordsKey = "vinetrack_damage_records"
    let historicalYieldRecordsKey = "vinetrack_historical_yield_records"
    var maintenanceLogsKey: String { MaintenanceLogRepository.storageKey }
    var workTasksKey: String { WorkTaskRepository.storageKey }
    let grapeVarietiesKey = "vinetrack_grape_varieties"

    static let storageDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("VineTrackData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var selectedVineyard: Vineyard? {
        vineyards.first { $0.id == selectedVineyardId }
    }

    init() {
        migrateFromUserDefaultsIfNeeded()
        load()
    }

    func load() {
        vineyards = loadData(key: vineyardsKey) ?? []
        if let savedId = UserDefaults.standard.string(forKey: selectedVineyardIdKey) {
            selectedVineyardId = UUID(uuidString: savedId)
        }
        if selectedVineyardId == nil, let first = vineyards.first {
            selectedVineyardId = first.id
        }
        loadVineyardData()
    }

    func reloadCurrentVineyardData() {
        loadVineyardData()
    }

    private func loadVineyardData() {
        let allPins: [VinePin] = loadData(key: pinsKey) ?? []
        let allPaddocks: [Paddock] = loadData(key: paddocksKey) ?? []
        let allTrips: [Trip] = loadData(key: tripsKey) ?? []
        let allRepairButtons: [ButtonConfig] = loadData(key: repairButtonsKey) ?? []
        let allGrowthButtons: [ButtonConfig] = loadData(key: growthButtonsKey) ?? []
        let allSettings: [AppSettings] = loadData(key: settingsKey) ?? []

        guard let vid = selectedVineyardId else {
            pins = []
            paddocks = []
            trips = []
            repairButtons = ButtonConfig.defaultRepairButtons(for: UUID())
            growthButtons = ButtonConfig.defaultGrowthButtons(for: UUID())
            settings = AppSettings()
            return
        }

        pins = allPins.filter { $0.vineyardId == vid }
        paddocks = allPaddocks.filter { $0.vineyardId == vid }
        trips = allTrips.filter { $0.vineyardId == vid }
        repairButtons = allRepairButtons.filter { $0.vineyardId == vid }
        growthButtons = allGrowthButtons.filter { $0.vineyardId == vid }

        if repairButtons.isEmpty {
            repairButtons = ButtonConfig.defaultRepairButtons(for: vid)
            saveAllRepairButtons()
        }
        if growthButtons.isEmpty {
            growthButtons = ButtonConfig.defaultGrowthButtons(for: vid)
            saveAllGrowthButtons()
        }

        settings = allSettings.first { $0.vineyardId == vid } ?? AppSettings(vineyardId: vid)

        let allCustomPatterns: [SavedCustomPattern] = loadData(key: customPatternsKey) ?? []
        savedCustomPatterns = allCustomPatterns.filter { $0.vineyardId == vid }

        let allSprayRecords: [SprayRecord] = loadData(key: sprayRecordsKey) ?? []
        sprayRecords = allSprayRecords.filter { $0.vineyardId == vid }

        let allSavedChemicals: [SavedChemical] = loadData(key: savedChemicalsKey) ?? []
        savedChemicals = allSavedChemicals.filter { $0.vineyardId == vid }

        let allSavedPresets: [SavedSprayPreset] = loadData(key: savedSprayPresetsKey) ?? []
        savedSprayPresets = allSavedPresets.filter { $0.vineyardId == vid }

        let allEquipmentOptions: [SavedEquipmentOption] = loadData(key: savedEquipmentOptionsKey) ?? []
        savedEquipmentOptions = allEquipmentOptions.filter { $0.vineyardId == vid }

        let allSprayEquipment: [SprayEquipmentItem] = loadData(key: sprayEquipmentKey) ?? []
        sprayEquipment = allSprayEquipment.filter { $0.vineyardId == vid }

        let allTractors: [Tractor] = loadData(key: tractorsKey) ?? []
        tractors = allTractors.filter { $0.vineyardId == vid }

        let allFuelPurchases: [FuelPurchase] = loadData(key: fuelPurchasesKey) ?? []
        fuelPurchases = allFuelPurchases.filter { $0.vineyardId == vid }

        let allOperatorCategories: [OperatorCategory] = loadData(key: operatorCategoriesKey) ?? []
        operatorCategories = allOperatorCategories.filter { $0.vineyardId == vid }

        let allButtonTemplates: [ButtonTemplate] = loadData(key: buttonTemplatesKey) ?? []
        buttonTemplates = allButtonTemplates.filter { $0.vineyardId == vid }

        let allYieldSessions: [YieldEstimationSession] = loadData(key: yieldSessionsKey) ?? []
        yieldSessions = allYieldSessions.filter { $0.vineyardId == vid }

        let allDamageRecords: [DamageRecord] = loadData(key: damageRecordsKey) ?? []
        damageRecords = allDamageRecords.filter { $0.vineyardId == vid }

        let allHistoricalYield: [HistoricalYieldRecord] = loadData(key: historicalYieldRecordsKey) ?? []
        historicalYieldRecords = allHistoricalYield.filter { $0.vineyardId == vid }

        maintenanceLogs = maintenanceLogRepository.load(for: vid)
        workTasks = workTaskRepository.load(for: vid)

        let allGrapeVarieties: [GrapeVariety] = loadData(key: grapeVarietiesKey) ?? []
        grapeVarieties = allGrapeVarieties.filter { $0.vineyardId == vid }
        if grapeVarieties.isEmpty {
            grapeVarieties = GrapeVariety.defaults(for: vid)
            saveAllGrapeVarieties()
        } else {
            let defaults = GrapeVariety.defaults(for: vid)
            let existingBuiltInNames = Set(grapeVarieties.filter { $0.isBuiltIn }.map { $0.name })
            let defaultNames = Set(defaults.map { $0.name })
            if existingBuiltInNames != defaultNames {
                grapeVarieties.removeAll { $0.isBuiltIn }
                grapeVarieties.append(contentsOf: defaults)
                saveAllGrapeVarieties()
            }
        }

        if operatorCategories.isEmpty {
            let defaultCategory = OperatorCategory(vineyardId: vid, name: "Tractor Operator", costPerHour: 40)
            operatorCategories = [defaultCategory]
            saveAllOperatorCategories()
            assignDefaultOperatorCategory(defaultCategory.id, vineyardId: vid)
        }

        analytics?.setVineyard(vid)
    }

    // MARK: - Cloud Sync Helpers (read all data)

    var allPins: [VinePin] { loadData(key: pinsKey) ?? [] }
    var allPaddocks: [Paddock] { loadData(key: paddocksKey) ?? [] }
    var allTrips: [Trip] { loadData(key: tripsKey) ?? [] }
    var allRepairButtons: [ButtonConfig] { loadData(key: repairButtonsKey) ?? [] }
    var allGrowthButtons: [ButtonConfig] { loadData(key: growthButtonsKey) ?? [] }
    var allSettings: [AppSettings] { loadData(key: settingsKey) ?? [] }
    var allCustomPatterns: [SavedCustomPattern] { loadData(key: customPatternsKey) ?? [] }
    var allSprayRecords: [SprayRecord] { loadData(key: sprayRecordsKey) ?? [] }
    var allSavedChemicals: [SavedChemical] { loadData(key: savedChemicalsKey) ?? [] }
    var allSavedSprayPresets: [SavedSprayPreset] { loadData(key: savedSprayPresetsKey) ?? [] }
    var allSavedEquipmentOptions: [SavedEquipmentOption] { loadData(key: savedEquipmentOptionsKey) ?? [] }
    var allSprayEquipment: [SprayEquipmentItem] { loadData(key: sprayEquipmentKey) ?? [] }
    var allTractors: [Tractor] { loadData(key: tractorsKey) ?? [] }
    var allFuelPurchases: [FuelPurchase] { loadData(key: fuelPurchasesKey) ?? [] }
    var allOperatorCategories: [OperatorCategory] { loadData(key: operatorCategoriesKey) ?? [] }
    var allButtonTemplates: [ButtonTemplate] { loadData(key: buttonTemplatesKey) ?? [] }

    var chemicals: [SavedChemical] { savedChemicals }
    var equipment: [SprayEquipmentItem] { sprayEquipment }
    var phenologyStages: [PhenologyStage] { PhenologyStage.allStages }
    var seasonFuelCostPerLitre: Double {
        guard !fuelPurchases.isEmpty else { return settings.seasonFuelCostPerLitre }
        let totalCost = fuelPurchases.reduce(0) { $0 + $1.totalCost }
        let totalVol = fuelPurchases.reduce(0) { $0 + $1.volumeLitres }
        guard totalVol > 0 else { return settings.seasonFuelCostPerLitre }
        return totalCost / totalVol
    }

    // MARK: - Vineyard CRUD

    func backfillVineyardOwner(userId: String, userName: String) {
        var changed = false
        for i in vineyards.indices where vineyards[i].users.isEmpty {
            let owner = VineyardUser(
                id: UUID(uuidString: userId) ?? UUID(),
                name: userName,
                role: .owner
            )
            vineyards[i].users = [owner]
            changed = true
        }
        if changed {
            save(vineyards, key: vineyardsKey)
        }
    }

    func addVineyard(_ vineyard: Vineyard) {
        vineyards.append(vineyard)
        save(vineyards, key: vineyardsKey)
        if selectedVineyardId == nil {
            selectedVineyardId = vineyard.id
        }
        analytics?.track("vineyard_created", data: ["name": vineyard.name])
        syncVineyardToCloud(vineyard)
    }

    func updateVineyard(_ vineyard: Vineyard) {
        guard let index = vineyards.firstIndex(where: { $0.id == vineyard.id }) else { return }
        vineyards[index] = vineyard
        save(vineyards, key: vineyardsKey)
        syncVineyardToCloud(vineyard)
    }

    func deleteVineyard(_ vineyard: Vineyard) {
        guard assertCanDelete("Vineyard") else { return }
        let vid = vineyard.id
        vineyards.removeAll { $0.id == vid }
        save(vineyards, key: vineyardsKey)

        var allPins: [VinePin] = loadData(key: pinsKey) ?? []
        allPins.removeAll { $0.vineyardId == vid }
        save(allPins, key: pinsKey)

        var allPaddocks: [Paddock] = loadData(key: paddocksKey) ?? []
        allPaddocks.removeAll { $0.vineyardId == vid }
        save(allPaddocks, key: paddocksKey)

        var allTrips: [Trip] = loadData(key: tripsKey) ?? []
        allTrips.removeAll { $0.vineyardId == vid }
        save(allTrips, key: tripsKey)

        var allRepairButtons: [ButtonConfig] = loadData(key: repairButtonsKey) ?? []
        allRepairButtons.removeAll { $0.vineyardId == vid }
        save(allRepairButtons, key: repairButtonsKey)

        var allGrowthButtons: [ButtonConfig] = loadData(key: growthButtonsKey) ?? []
        allGrowthButtons.removeAll { $0.vineyardId == vid }
        save(allGrowthButtons, key: growthButtonsKey)

        var allSettings: [AppSettings] = loadData(key: settingsKey) ?? []
        allSettings.removeAll { $0.vineyardId == vid }
        save(allSettings, key: settingsKey)

        if selectedVineyardId == vid {
            selectedVineyardId = vineyards.first?.id
        }

        analytics?.track("vineyard_deleted")
        Task { await cloudSync?.deleteVineyardFromCloud(vid) }
    }

    func selectVineyard(_ vineyard: Vineyard) {
        selectedVineyardId = vineyard.id
    }

    // MARK: - Pin CRUD

    func addPin(_ pin: VinePin) {
        guard let vid = selectedVineyardId else { return }
        var newPin = pin
        newPin.vineyardId = vid
        if let activeTrip = activeTrip {
            newPin.tripId = activeTrip.id
        }
        pins.insert(newPin, at: 0)
        saveAllPins()
        if var trip = activeTrip {
            trip.pinIds.append(newPin.id)
            updateTrip(trip)
        }
        analytics?.track("pin_created", data: ["mode": pin.mode.rawValue, "button": pin.buttonName])
    }

    func togglePinCompletion(_ pin: VinePin, by userName: String? = nil) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        pins[index].isCompleted.toggle()
        if pins[index].isCompleted {
            pins[index].completedBy = userName
            pins[index].completedAt = Date()
            analytics?.track("pin_completed")
        } else {
            pins[index].completedBy = nil
            pins[index].completedAt = nil
        }
        saveAllPins()
    }

    func updatePin(_ pin: VinePin) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        pins[index] = pin
        saveAllPins()
    }

    func deletePin(_ pin: VinePin) {
        guard assertCanDelete("Pin") else { return }
        pins.removeAll { $0.id == pin.id }
        saveAllPins()
    }

    func deletePins(at offsets: IndexSet, from filteredPins: [VinePin]) {
        guard assertCanDelete("Pins") else { return }
        let idsToDelete = offsets.map { filteredPins[$0].id }
        pins.removeAll { idsToDelete.contains($0.id) }
        saveAllPins()
    }

    // MARK: - Paddock CRUD

    func addPaddock(_ paddock: Paddock) {
        guard let vid = selectedVineyardId else { return }
        var newPaddock = paddock
        newPaddock.vineyardId = vid
        paddocks.append(newPaddock)
        saveAllPaddocks()
        analytics?.track("paddock_created", data: ["name": paddock.name])
        autoDetectVineyardCountryIfNeeded(from: newPaddock)
    }

    func updatePaddock(_ paddock: Paddock) {
        guard let index = paddocks.firstIndex(where: { $0.id == paddock.id }) else { return }
        paddocks[index] = paddock
        saveAllPaddocks()
        autoDetectVineyardCountryIfNeeded(from: paddock)
    }

    func deletePaddock(_ paddock: Paddock) {
        guard assertCanDelete("Paddock") else { return }
        paddocks.removeAll { $0.id == paddock.id }
        saveAllPaddocks()
        auditService?.log(action: .delete, entityType: "Paddock", entityId: paddock.id.uuidString, entityLabel: paddock.name)
    }

    // MARK: - Trip CRUD

    func startTrip(_ trip: Trip) {
        guard let vid = selectedVineyardId else { return }
        var newTrip = trip
        newTrip.vineyardId = vid
        trips.insert(newTrip, at: 0)
        saveAllTrips()
        analytics?.track("trip_started", data: ["pattern": trip.trackingPattern.rawValue])
    }

    func updateTrip(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        saveAllTrips()
    }

    func endTrip(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        let now = Date()
        trips[index].isActive = false
        trips[index].endTime = now
        trips[index].isPaused = false
        saveAllTrips()

        if let recIndex = sprayRecords.firstIndex(where: { $0.tripId == trip.id }) {
            sprayRecords[recIndex].endTime = now
            let durationSeconds = trips[index].activeDuration
            if durationSeconds > 0 && trip.totalDistance > 0 {
                let distanceKm = trip.totalDistance / 1000.0
                let hours = durationSeconds / 3600.0
                sprayRecords[recIndex].averageSpeed = distanceKm / hours
            }
            saveAllSprayRecords()
        }

        analytics?.track("trip_ended", data: ["distance": String(format: "%.0f", trip.totalDistance)])
    }

    func deleteTrip(_ trip: Trip) {
        guard assertCanDelete("Trip") else { return }
        trips.removeAll { $0.id == trip.id }
        saveAllTrips()
        auditService?.log(
            action: .delete,
            entityType: "Trip",
            entityId: trip.id.uuidString,
            entityLabel: trip.paddockName,
            details: "Deleted trip from \(trip.startTime.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    // MARK: - Buttons

    func updateRepairButtons(_ buttons: [ButtonConfig]) {
        repairButtons = buttons
        saveAllRepairButtons()
    }

    func updateGrowthButtons(_ buttons: [ButtonConfig]) {
        growthButtons = buttons
        saveAllGrowthButtons()
    }

    // MARK: - Custom Patterns

    func addCustomPattern(_ pattern: SavedCustomPattern) {
        guard let vid = selectedVineyardId else { return }
        var newPattern = pattern
        newPattern.vineyardId = vid
        savedCustomPatterns.append(newPattern)
        saveAllCustomPatterns()
    }

    func updateCustomPattern(_ pattern: SavedCustomPattern) {
        guard let index = savedCustomPatterns.firstIndex(where: { $0.id == pattern.id }) else { return }
        savedCustomPatterns[index] = pattern
        saveAllCustomPatterns()
    }

    func deleteCustomPattern(_ pattern: SavedCustomPattern) {
        guard assertCanDelete("CustomPattern") else { return }
        savedCustomPatterns.removeAll { $0.id == pattern.id }
        saveAllCustomPatterns()
    }

    // MARK: - Spray Records

    func addSprayRecord(_ record: SprayRecord) {
        guard let vid = selectedVineyardId else { return }
        var newRecord = record
        newRecord.vineyardId = vid
        sprayRecords.insert(newRecord, at: 0)
        saveAllSprayRecords()
        analytics?.track("spray_record_created")
    }

    func updateSprayRecord(_ record: SprayRecord) {
        guard let index = sprayRecords.firstIndex(where: { $0.id == record.id }) else { return }
        sprayRecords[index] = record
        saveAllSprayRecords()
    }

    func deleteSprayRecord(_ record: SprayRecord) {
        guard assertCanDelete("SprayRecord") else { return }
        sprayRecords.removeAll { $0.id == record.id }
        saveAllSprayRecords()
        auditService?.log(
            action: .delete,
            entityType: "SprayRecord",
            entityId: record.id.uuidString,
            entityLabel: record.sprayReference,
            details: "Deleted spray record"
        )
    }

    func sprayRecord(for tripId: UUID) -> SprayRecord? {
        sprayRecords.first { $0.tripId == tripId }
    }

    // MARK: - Saved Chemicals

    func addSavedChemical(_ chemical: SavedChemical) {
        guard let vid = selectedVineyardId else { return }
        var newChemical = chemical
        newChemical.vineyardId = vid
        savedChemicals.append(newChemical)
        saveAllSavedChemicals()
    }

    func updateSavedChemical(_ chemical: SavedChemical) {
        guard let index = savedChemicals.firstIndex(where: { $0.id == chemical.id }) else { return }
        savedChemicals[index] = chemical
        saveAllSavedChemicals()
    }

    func deleteSavedChemical(_ chemical: SavedChemical) {
        guard assertCanDelete("SavedChemical") else { return }
        savedChemicals.removeAll { $0.id == chemical.id }
        saveAllSavedChemicals()
    }

    // MARK: - Saved Spray Presets

    func addSavedSprayPreset(_ preset: SavedSprayPreset) {
        guard let vid = selectedVineyardId else { return }
        var newPreset = preset
        newPreset.vineyardId = vid
        savedSprayPresets.append(newPreset)
        saveAllSavedSprayPresets()
    }

    func updateSavedSprayPreset(_ preset: SavedSprayPreset) {
        guard let index = savedSprayPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        savedSprayPresets[index] = preset
        saveAllSavedSprayPresets()
    }

    func deleteSavedSprayPreset(_ preset: SavedSprayPreset) {
        guard assertCanDelete("SprayPreset") else { return }
        savedSprayPresets.removeAll { $0.id == preset.id }
        saveAllSavedSprayPresets()
    }

    // MARK: - Saved Equipment Options

    func equipmentOptions(for category: String) -> [SavedEquipmentOption] {
        savedEquipmentOptions.filter { $0.category == category }
    }

    func addEquipmentOption(_ option: SavedEquipmentOption) {
        guard let vid = selectedVineyardId else { return }
        let trimmed = option.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if savedEquipmentOptions.contains(where: { $0.category == option.category && $0.value.lowercased() == trimmed.lowercased() }) {
            return
        }
        var newOption = option
        newOption.vineyardId = vid
        savedEquipmentOptions.append(newOption)
        saveAllSavedEquipmentOptions()
    }

    func deleteEquipmentOption(_ option: SavedEquipmentOption) {
        guard assertCanDelete("EquipmentOption") else { return }
        savedEquipmentOptions.removeAll { $0.id == option.id }
        saveAllSavedEquipmentOptions()
    }

    // MARK: - Spray Equipment

    func addSprayEquipment(_ item: SprayEquipmentItem) {
        guard let vid = selectedVineyardId else { return }
        var newItem = item
        newItem.vineyardId = vid
        sprayEquipment.append(newItem)
        saveAllSprayEquipment()
    }

    func updateSprayEquipment(_ item: SprayEquipmentItem) {
        guard let index = sprayEquipment.firstIndex(where: { $0.id == item.id }) else { return }
        sprayEquipment[index] = item
        saveAllSprayEquipment()
    }

    func deleteSprayEquipment(_ item: SprayEquipmentItem) {
        guard assertCanDelete("SprayEquipment") else { return }
        sprayEquipment.removeAll { $0.id == item.id }
        saveAllSprayEquipment()
    }

    // MARK: - Tractors

    func addTractor(_ tractor: Tractor) {
        guard let vid = selectedVineyardId else { return }
        var newTractor = tractor
        newTractor.vineyardId = vid
        tractors.append(newTractor)
        saveAllTractors()
    }

    func updateTractor(_ tractor: Tractor) {
        guard let index = tractors.firstIndex(where: { $0.id == tractor.id }) else { return }
        tractors[index] = tractor
        saveAllTractors()
    }

    func deleteTractor(_ tractor: Tractor) {
        guard assertCanDelete("Tractor") else { return }
        tractors.removeAll { $0.id == tractor.id }
        saveAllTractors()
    }

    // MARK: - Fuel Purchases

    func addFuelPurchase(_ purchase: FuelPurchase) {
        guard let vid = selectedVineyardId else { return }
        var newPurchase = purchase
        newPurchase.vineyardId = vid
        fuelPurchases.append(newPurchase)
        saveAllFuelPurchases()
    }

    func updateFuelPurchase(_ purchase: FuelPurchase) {
        guard let index = fuelPurchases.firstIndex(where: { $0.id == purchase.id }) else { return }
        fuelPurchases[index] = purchase
        saveAllFuelPurchases()
    }

    func deleteFuelPurchase(_ purchase: FuelPurchase) {
        guard assertCanDelete("FuelPurchase") else { return }
        fuelPurchases.removeAll { $0.id == purchase.id }
        saveAllFuelPurchases()
    }

    // MARK: - Operator Categories

    func addOperatorCategory(_ category: OperatorCategory) {
        guard let vid = selectedVineyardId else { return }
        var newCategory = category
        newCategory.vineyardId = vid
        operatorCategories.append(newCategory)
        saveAllOperatorCategories()
    }

    func updateOperatorCategory(_ category: OperatorCategory) {
        guard let index = operatorCategories.firstIndex(where: { $0.id == category.id }) else { return }
        operatorCategories[index] = category
        saveAllOperatorCategories()
    }

    func deleteOperatorCategory(_ category: OperatorCategory) {
        guard assertCanChangeSettings("OperatorCategory") else { return }
        operatorCategories.removeAll { $0.id == category.id }
        saveAllOperatorCategories()
    }

    func operatorCategory(for userId: UUID) -> OperatorCategory? {
        guard let vineyard = selectedVineyard,
              let user = vineyard.users.first(where: { $0.id == userId }),
              let catId = user.operatorCategoryId else { return nil }
        return operatorCategories.first { $0.id == catId }
    }

    func operatorCategoryForName(_ personName: String) -> OperatorCategory? {
        guard let vineyard = selectedVineyard else { return nil }
        guard let user = vineyard.users.first(where: { $0.name.lowercased() == personName.lowercased() }),
              let catId = user.operatorCategoryId else { return nil }
        return operatorCategories.first { $0.id == catId }
    }

    func assignDefaultOperatorCategory(_ categoryId: UUID, vineyardId: UUID) {
        guard let index = vineyards.firstIndex(where: { $0.id == vineyardId }) else { return }
        for userIndex in vineyards[index].users.indices {
            if vineyards[index].users[userIndex].operatorCategoryId == nil {
                vineyards[index].users[userIndex].operatorCategoryId = categoryId
            }
        }
        save(vineyards, key: vineyardsKey)
    }

    // MARK: - Button Templates

    func addButtonTemplate(_ template: ButtonTemplate) {
        guard let vid = selectedVineyardId else { return }
        var newTemplate = template
        newTemplate.vineyardId = vid
        buttonTemplates.append(newTemplate)
        saveAllButtonTemplates()
    }

    func updateButtonTemplate(_ template: ButtonTemplate) {
        guard let index = buttonTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        buttonTemplates[index] = template
        saveAllButtonTemplates()
    }

    func deleteButtonTemplate(_ template: ButtonTemplate) {
        guard assertCanChangeSettings("ButtonTemplate") else { return }
        buttonTemplates.removeAll { $0.id == template.id }
        saveAllButtonTemplates()
    }

    // MARK: - Damage Records

    func addDamageRecord(_ record: DamageRecord) {
        guard let vid = selectedVineyardId else { return }
        var newRecord = record
        newRecord.vineyardId = vid
        damageRecords.append(newRecord)
        saveAllDamageRecords()
    }

    func updateDamageRecord(_ record: DamageRecord) {
        guard let index = damageRecords.firstIndex(where: { $0.id == record.id }) else { return }
        damageRecords[index] = record
        saveAllDamageRecords()
    }

    func deleteDamageRecord(_ record: DamageRecord) {
        guard assertCanDelete("DamageRecord") else { return }
        damageRecords.removeAll { $0.id == record.id }
        saveAllDamageRecords()
    }

    func damageRecords(for paddockId: UUID) -> [DamageRecord] {
        damageRecords.filter { $0.paddockId == paddockId }
    }

    func damageFactor(for paddockId: UUID) -> Double {
        let records = damageRecords.filter { $0.paddockId == paddockId }
        guard !records.isEmpty else { return 1.0 }
        guard let paddock = paddocks.first(where: { $0.id == paddockId }) else { return 1.0 }
        let blockArea = paddock.areaHectares
        guard blockArea > 0 else { return 1.0 }
        var totalLostHa: Double = 0
        for record in records {
            let damageArea = min(record.areaHectares, blockArea)
            let lostHa = damageArea * (record.damagePercent / 100.0)
            totalLostHa += lostHa
        }
        let factor = max(0, 1.0 - (totalLostHa / blockArea))
        return factor
    }

    // MARK: - Maintenance Logs

    func addMaintenanceLog(_ log: MaintenanceLog) {
        guard let vid = selectedVineyardId else { return }
        var newLog = log
        newLog.vineyardId = vid
        maintenanceLogs.insert(newLog, at: 0)
        saveAllMaintenanceLogs()
        analytics?.track("maintenance_log_created", data: ["item": log.itemName])
    }

    func updateMaintenanceLog(_ log: MaintenanceLog) {
        guard let index = maintenanceLogs.firstIndex(where: { $0.id == log.id }) else { return }
        maintenanceLogs[index] = log
        saveAllMaintenanceLogs()
    }

    func deleteMaintenanceLog(_ log: MaintenanceLog) {
        guard assertCanDelete("MaintenanceLog") else { return }
        maintenanceLogs.removeAll { $0.id == log.id }
        saveAllMaintenanceLogs()
        auditService?.log(
            action: .delete,
            entityType: "MaintenanceLog",
            entityId: log.id.uuidString,
            entityLabel: log.itemName
        )
    }

    func archiveMaintenanceLog(_ log: MaintenanceLog) {
        guard assertCanDelete("ArchiveMaintenanceLog") else { return }
        guard let index = maintenanceLogs.firstIndex(where: { $0.id == log.id }) else { return }
        maintenanceLogs[index].isArchived = true
        maintenanceLogs[index].archivedAt = Date()
        maintenanceLogs[index].archivedBy = authService?.userName
        saveAllMaintenanceLogs()
        auditService?.log(
            action: .softDelete,
            entityType: "MaintenanceLog",
            entityId: log.id.uuidString,
            entityLabel: log.itemName
        )
    }

    func restoreMaintenanceLog(_ log: MaintenanceLog) {
        guard assertCanDelete("RestoreMaintenanceLog") else { return }
        guard let index = maintenanceLogs.firstIndex(where: { $0.id == log.id }) else { return }
        maintenanceLogs[index].isArchived = false
        maintenanceLogs[index].archivedAt = nil
        maintenanceLogs[index].archivedBy = nil
        saveAllMaintenanceLogs()
        auditService?.log(
            action: .restore,
            entityType: "MaintenanceLog",
            entityId: log.id.uuidString,
            entityLabel: log.itemName
        )
    }

    func finalizeMaintenanceLog(_ log: MaintenanceLog) {
        guard let ac = accessControl, ac.canFinalizeRecords else {
            #if DEBUG
            print("⛔️ Permission denied: finalize MaintenanceLog")
            #endif
            return
        }
        guard let index = maintenanceLogs.firstIndex(where: { $0.id == log.id }) else { return }
        maintenanceLogs[index].isFinalized = true
        maintenanceLogs[index].finalizedAt = Date()
        maintenanceLogs[index].finalizedBy = authService?.userName
        saveAllMaintenanceLogs()
        auditService?.log(
            action: .recordFinalized,
            entityType: "MaintenanceLog",
            entityId: log.id.uuidString,
            entityLabel: log.itemName
        )
    }

    func reopenMaintenanceLog(_ log: MaintenanceLog) {
        guard let ac = accessControl, ac.canReopenRecords else {
            #if DEBUG
            print("⛔️ Permission denied: reopen MaintenanceLog")
            #endif
            return
        }
        guard let index = maintenanceLogs.firstIndex(where: { $0.id == log.id }) else { return }
        maintenanceLogs[index].isFinalized = false
        maintenanceLogs[index].finalizedAt = nil
        maintenanceLogs[index].finalizedBy = nil
        saveAllMaintenanceLogs()
        auditService?.log(
            action: .recordReopened,
            entityType: "MaintenanceLog",
            entityId: log.id.uuidString,
            entityLabel: log.itemName
        )
    }

    // MARK: - Work Tasks

    func addWorkTask(_ task: WorkTask) {
        guard let vid = selectedVineyardId else { return }
        var t = task
        t.vineyardId = vid
        workTasks.insert(t, at: 0)
        saveAllWorkTasks()
        analytics?.track("work_task_created", data: ["type": task.taskType])
    }

    func updateWorkTask(_ task: WorkTask) {
        guard let index = workTasks.firstIndex(where: { $0.id == task.id }) else { return }
        workTasks[index] = task
        saveAllWorkTasks()
    }

    func deleteWorkTask(_ task: WorkTask) {
        guard assertCanDelete("WorkTask") else { return }
        workTasks.removeAll { $0.id == task.id }
        saveAllWorkTasks()
        auditService?.log(
            action: .delete,
            entityType: "WorkTask",
            entityId: task.id.uuidString,
            entityLabel: task.taskType
        )
    }

    func archiveWorkTask(_ task: WorkTask) {
        guard assertCanDelete("ArchiveWorkTask") else { return }
        guard let index = workTasks.firstIndex(where: { $0.id == task.id }) else { return }
        workTasks[index].isArchived = true
        workTasks[index].archivedAt = Date()
        workTasks[index].archivedBy = authService?.userName
        saveAllWorkTasks()
        auditService?.log(
            action: .softDelete,
            entityType: "WorkTask",
            entityId: task.id.uuidString,
            entityLabel: task.taskType
        )
    }

    func restoreWorkTask(_ task: WorkTask) {
        guard assertCanDelete("RestoreWorkTask") else { return }
        guard let index = workTasks.firstIndex(where: { $0.id == task.id }) else { return }
        workTasks[index].isArchived = false
        workTasks[index].archivedAt = nil
        workTasks[index].archivedBy = nil
        saveAllWorkTasks()
        auditService?.log(
            action: .restore,
            entityType: "WorkTask",
            entityId: task.id.uuidString,
            entityLabel: task.taskType
        )
    }

    func finalizeWorkTask(_ task: WorkTask) {
        guard let ac = accessControl, ac.canFinalizeRecords else {
            #if DEBUG
            print("⛔️ Permission denied: finalize WorkTask")
            #endif
            return
        }
        guard let index = workTasks.firstIndex(where: { $0.id == task.id }) else { return }
        workTasks[index].isFinalized = true
        workTasks[index].finalizedAt = Date()
        workTasks[index].finalizedBy = authService?.userName
        saveAllWorkTasks()
        auditService?.log(
            action: .recordFinalized,
            entityType: "WorkTask",
            entityId: task.id.uuidString,
            entityLabel: task.taskType
        )
    }

    func reopenWorkTask(_ task: WorkTask) {
        guard let ac = accessControl, ac.canReopenRecords else {
            #if DEBUG
            print("⛔️ Permission denied: reopen WorkTask")
            #endif
            return
        }
        guard let index = workTasks.firstIndex(where: { $0.id == task.id }) else { return }
        workTasks[index].isFinalized = false
        workTasks[index].finalizedAt = nil
        workTasks[index].finalizedBy = nil
        saveAllWorkTasks()
        auditService?.log(
            action: .recordReopened,
            entityType: "WorkTask",
            entityId: task.id.uuidString,
            entityLabel: task.taskType
        )
    }

    func saveAllWorkTasks() {
        guard let vid = selectedVineyardId else { return }
        workTaskRepository.saveSlice(workTasks, for: vid)
        syncDataToCloud(dataType: "work_tasks")
    }

    func replaceWorkTasks(_ remote: [WorkTask], for vineyardId: UUID) {
        workTaskRepository.replace(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            workTasks = remote
        }
    }

    func mergeWorkTasks(_ remote: [WorkTask], for vineyardId: UUID) {
        let merged = workTaskRepository.merge(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            workTasks = merged
        }
    }

    // MARK: - Grape Varieties

    func addGrapeVariety(_ variety: GrapeVariety) {
        guard let vid = selectedVineyardId else { return }
        var v = variety
        v.vineyardId = vid
        grapeVarieties.append(v)
        saveAllGrapeVarieties()
    }

    func updateGrapeVariety(_ variety: GrapeVariety) {
        guard let index = grapeVarieties.firstIndex(where: { $0.id == variety.id }) else { return }
        grapeVarieties[index] = variety
        saveAllGrapeVarieties()
    }

    func deleteGrapeVariety(_ variety: GrapeVariety) {
        guard assertCanChangeSettings("GrapeVariety") else { return }
        grapeVarieties.removeAll { $0.id == variety.id }
        saveAllGrapeVarieties()
    }

    func grapeVariety(for id: UUID) -> GrapeVariety? {
        grapeVarieties.first { $0.id == id }
    }

    func saveAllGrapeVarieties() {
        var all: [GrapeVariety] = loadData(key: grapeVarietiesKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: grapeVarieties)
        save(all, key: grapeVarietiesKey)
        syncDataToCloud(dataType: "grape_varieties")
    }

    func replaceGrapeVarieties(_ remote: [GrapeVariety], for vineyardId: UUID) {
        var all: [GrapeVariety] = loadData(key: grapeVarietiesKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: grapeVarietiesKey)
        if selectedVineyardId == vineyardId {
            grapeVarieties = remote
        }
    }

    func mergeGrapeVarieties(_ remote: [GrapeVariety], for vineyardId: UUID) {
        var all: [GrapeVariety] = loadData(key: grapeVarietiesKey) ?? []
        for item in remote {
            if let index = all.firstIndex(where: { $0.id == item.id }) {
                all[index] = item
            } else {
                all.append(item)
            }
        }
        save(all, key: grapeVarietiesKey)
        if selectedVineyardId == vineyardId {
            grapeVarieties = all.filter { $0.vineyardId == vineyardId }
        }
    }

    var allGrapeVarieties: [GrapeVariety] {
        loadData(key: grapeVarietiesKey) ?? []
    }

    // MARK: - Historical Yield Records

    func addHistoricalYieldRecord(_ record: HistoricalYieldRecord) {
        guard let vid = selectedVineyardId else { return }
        var newRecord = record
        newRecord.vineyardId = vid
        historicalYieldRecords.append(newRecord)
        saveAllHistoricalYieldRecords()
    }

    func updateHistoricalYieldRecord(_ record: HistoricalYieldRecord) {
        guard let index = historicalYieldRecords.firstIndex(where: { $0.id == record.id }) else { return }
        historicalYieldRecords[index] = record
        saveAllHistoricalYieldRecords()
    }

    func deleteHistoricalYieldRecord(_ record: HistoricalYieldRecord) {
        guard assertCanDelete("HistoricalYield") else { return }
        historicalYieldRecords.removeAll { $0.id == record.id }
        saveAllHistoricalYieldRecords()
    }

    // MARK: - Yield Sessions

    func saveYieldSession(_ session: YieldEstimationSession) {
        if let index = yieldSessions.firstIndex(where: { $0.id == session.id }) {
            yieldSessions[index] = session
        } else {
            yieldSessions.removeAll { $0.vineyardId == session.vineyardId }
            yieldSessions.append(session)
        }
        saveAllYieldSessions()
    }

    func deleteYieldSession(_ session: YieldEstimationSession) {
        guard assertCanDelete("YieldSession") else { return }
        yieldSessions.removeAll { $0.id == session.id }
        saveAllYieldSessions()
    }

    func applyButtonTemplate(_ template: ButtonTemplate) {
        guard let vid = selectedVineyardId else { return }
        let configs = template.toButtonConfigs(for: vid)
        switch template.mode {
        case .repairs:
            updateRepairButtons(configs)
        case .growth:
            updateGrowthButtons(configs)
        }
    }

    func buttonTemplates(for mode: PinMode) -> [ButtonTemplate] {
        buttonTemplates.filter { $0.mode == mode }
    }

    func ensureDefaultRepairTemplate() {
        guard let vid = selectedVineyardId else { return }
        let repairTemplates = buttonTemplates.filter { $0.mode == .repairs }
        guard repairTemplates.isEmpty else { return }
        let leftButtons = repairButtons.sorted { $0.index < $1.index }.filter { $0.index < 4 }
        guard !leftButtons.isEmpty else { return }
        let entries = leftButtons.map { ButtonTemplateEntry(name: $0.name, color: $0.color, isGrowthStageButton: $0.isGrowthStageButton) }
        let template = ButtonTemplate(vineyardId: vid, name: "Repairs 1", mode: .repairs, entries: entries)
        buttonTemplates.append(template)
        saveAllButtonTemplates()
    }

    func ensureDefaultGrowthTemplate() {
        guard let vid = selectedVineyardId else { return }
        let growthTemplates = buttonTemplates.filter { $0.mode == .growth }
        guard growthTemplates.isEmpty else { return }
        let leftButtons = growthButtons.sorted { $0.index < $1.index }.filter { $0.index < 4 }
        guard !leftButtons.isEmpty else { return }
        let entries = leftButtons.map { ButtonTemplateEntry(name: $0.name, color: $0.color, isGrowthStageButton: $0.isGrowthStageButton) }
        let template = ButtonTemplate(vineyardId: vid, name: "Growth 1", mode: .growth, entries: entries)
        buttonTemplates.append(template)
        saveAllButtonTemplates()
    }

    // MARK: - Spray Application

    func addSprayApplication(_ application: SprayApplication, tripId: UUID? = nil, tractorName: String = "") {
        guard let vid = selectedVineyardId else { return }
        let equipmentName = sprayEquipment.first(where: { $0.id == application.equipmentId })?.name ?? ""
        let equip = sprayEquipment.first(where: { $0.id == application.equipmentId })
        let tankCapacity = equip?.tankCapacityLitres ?? 0
        let selectedPaddocks = paddocks.filter { application.paddockIds.contains($0.id) }
        let waterRate = application.waterRateLitresPerHectare
        let cf = application.concentrationFactor

        let calcResult = SprayCalculator.calculate(
            selectedPaddocks: selectedPaddocks,
            waterRateLitresPerHectare: waterRate,
            tankCapacity: tankCapacity,
            chemicalLines: application.chemicalLines,
            chemicals: savedChemicals,
            concentrationFactor: cf,
            operationType: application.operationType
        )

        let numberOfTanks = calcResult.fullTankCount + (calcResult.lastTankLitres > 0 ? 1 : 0)
        var tanks: [SprayTank] = []
        for tankIndex in 0..<max(numberOfTanks, 1) {
            let isLastTank = tankIndex == numberOfTanks - 1
            let isPartialTank = isLastTank && calcResult.fullTankCount > 0 && calcResult.lastTankLitres > 0
            let waterVol = isPartialTank ? calcResult.lastTankLitres : (numberOfTanks > 0 ? tankCapacity : calcResult.totalWaterLitres)

            var chemicals: [SprayChemical] = []
            for chemResult in calcResult.chemicalResults {
                let volume = isPartialTank ? chemResult.amountInLastTank : chemResult.amountPerFullTank
                let costPerUnit: Double
                if let chem = savedChemicals.first(where: { $0.name == chemResult.chemicalName }),
                   let purchase = chem.purchase {
                    costPerUnit = purchase.costPerBaseUnit
                } else {
                    costPerUnit = 0
                }
                chemicals.append(SprayChemical(
                    name: chemResult.chemicalName,
                    volumePerTank: volume,
                    ratePerHa: chemResult.selectedRate,
                    costPerUnit: costPerUnit,
                    unit: chemResult.unit
                ))
            }

            tanks.append(SprayTank(
                tankNumber: tankIndex + 1,
                waterVolume: waterVol,
                sprayRatePerHa: waterRate,
                concentrationFactor: cf,
                chemicals: chemicals
            ))
        }

        var notesParts: [String] = []
        if !application.notes.isEmpty { notesParts.append(application.notes) }
        let record = SprayRecord(
            tripId: tripId ?? UUID(),
            vineyardId: vid,
            date: application.jobStartDate ?? Date(),
            startTime: application.jobStartDate ?? Date(),
            temperature: application.weather?.temperature,
            windSpeed: application.weather?.windSpeed,
            windDirection: application.weather?.windDirection ?? "",
            humidity: application.weather?.humidity,
            sprayReference: application.sprayName,
            tanks: tanks,
            notes: notesParts.joined(separator: "\n"),
            numberOfFansJets: application.numberOfFansJets,
            equipmentType: equipmentName,
            tractor: tractorName,
            tractorGear: application.tractorGear,
            operationType: application.operationType
        )
        addSprayRecord(record)
    }

    // MARK: - Auto Country Detection

    private func autoDetectVineyardCountryIfNeeded(from paddock: Paddock) {
        guard let vid = selectedVineyardId,
              let vineyardIndex = vineyards.firstIndex(where: { $0.id == vid }) else { return }
        guard paddock.polygonPoints.count >= 3 else { return }
        let centroidLat = paddock.polygonPoints.map(\.latitude).reduce(0, +) / Double(paddock.polygonPoints.count)
        let centroidLon = paddock.polygonPoints.map(\.longitude).reduce(0, +) / Double(paddock.polygonPoints.count)
        let location = CLLocation(latitude: centroidLat, longitude: centroidLon)
        let geocoder = CLGeocoder()
        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let country = placemarks.first?.country, !country.isEmpty {
                    guard let idx = vineyards.firstIndex(where: { $0.id == vid }) else { return }
                    vineyards[idx].country = country
                    save(vineyards, key: vineyardsKey)
                    syncVineyardToCloud(vineyards[idx])
                }
            } catch {
                print("[AutoCountry] Reverse geocode failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Settings

    func updateVineyardLogo(_ logoData: Data?) {
        guard assertCanChangeSettings("VineyardLogo") else { return }
        guard let vid = selectedVineyardId,
              let index = vineyards.firstIndex(where: { $0.id == vid }) else { return }
        vineyards[index].logoData = logoData
        save(vineyards, key: vineyardsKey)
        syncVineyardToCloud(vineyards[index])
    }

    func updateSettings(_ newSettings: AppSettings) {
        guard assertCanChangeSettings("AppSettings") else { return }
        settings = newSettings
        var allSettings: [AppSettings] = loadData(key: settingsKey) ?? []
        if let index = allSettings.firstIndex(where: { $0.vineyardId == newSettings.vineyardId }) {
            allSettings[index] = newSettings
        } else {
            allSettings.append(newSettings)
        }
        save(allSettings, key: settingsKey)
        syncDataToCloud(dataType: "settings")
        auditService?.log(
            action: .settingsChanged,
            entityType: "AppSettings",
            entityId: newSettings.vineyardId.uuidString,
            entityLabel: "Vineyard Settings"
        )
    }

    // MARK: - Delete All Data

    func deleteAllPins() {
        guard assertCanDelete("AllPins") else { return }
        pins = []
        saveAllPins()
    }

    func deleteAllTrips() {
        guard assertCanDelete("AllTrips") else { return }
        trips = []
        saveAllTrips()
    }

    func deleteAllData() {
        guard assertCanDelete("AllData") else { return }
        let keys = [pinsKey, paddocksKey, tripsKey, repairButtonsKey, growthButtonsKey, settingsKey, vineyardsKey, customPatternsKey, sprayRecordsKey, savedChemicalsKey, savedSprayPresetsKey, savedEquipmentOptionsKey, sprayEquipmentKey, tractorsKey, fuelPurchasesKey, operatorCategoriesKey, buttonTemplatesKey, yieldSessionsKey, damageRecordsKey, maintenanceLogsKey, workTasksKey]
        for key in keys {
            let fileURL = Self.storageDirectory.appendingPathComponent("\(key).json")
            try? FileManager.default.removeItem(at: fileURL)
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: selectedVineyardIdKey)
        UserDefaults.standard.removeObject(forKey: "vinetrack_migrated_to_files")
        pins = []
        paddocks = []
        trips = []
        vineyards = []
        repairButtons = []
        growthButtons = []
        settings = AppSettings()
        selectedVineyardId = nil
        savedCustomPatterns = []
        sprayRecords = []
        savedChemicals = []
        savedSprayPresets = []
        savedEquipmentOptions = []
        sprayEquipment = []
        tractors = []
        fuelPurchases = []
        operatorCategories = []
        buttonTemplates = []
        yieldSessions = []
        damageRecords = []
        historicalYieldRecords = []
        maintenanceLogs = []
        workTasks = []
    }

    func clearInMemoryState() {
        pins = []
        paddocks = []
        trips = []
        vineyards = []
        repairButtons = []
        growthButtons = []
        settings = AppSettings()
        selectedVineyardId = nil
        savedCustomPatterns = []
        sprayRecords = []
        savedChemicals = []
        savedSprayPresets = []
        savedEquipmentOptions = []
        sprayEquipment = []
        tractors = []
        fuelPurchases = []
        operatorCategories = []
        buttonTemplates = []
        yieldSessions = []
        damageRecords = []
        historicalYieldRecords = []
        maintenanceLogs = []
        workTasks = []
    }


    // MARK: - Computed

    var activeTrip: Trip? {
        trips.first { $0.isActive }
    }

    var paddockCentroidLatitude: Double? {
        let pts = paddocks.flatMap { $0.polygonPoints }
        guard !pts.isEmpty else { return nil }
        return pts.map(\.latitude).reduce(0, +) / Double(pts.count)
    }

    var paddockCentroidLongitude: Double? {
        let pts = paddocks.flatMap { $0.polygonPoints }
        guard !pts.isEmpty else { return nil }
        return pts.map(\.longitude).reduce(0, +) / Double(pts.count)
    }

    var orderedPaddocks: [Paddock] {
        let order = settings.paddockOrder
        guard !order.isEmpty else { return paddocks }
        return paddocks.sorted { a, b in
            let idxA = order.firstIndex(of: a.id) ?? Int.max
            let idxB = order.firstIndex(of: b.id) ?? Int.max
            return idxA < idxB
        }
    }

    func updatePaddockOrder(_ orderedIds: [UUID]) {
        var s = settings
        s.paddockOrder = orderedIds
        updateSettings(s)
    }

    func buttonsForMode(_ mode: PinMode) -> [ButtonConfig] {
        switch mode {
        case .repairs: return repairButtons.sorted { $0.index < $1.index }
        case .growth: return growthButtons.sorted { $0.index < $1.index }
        }
    }
}
