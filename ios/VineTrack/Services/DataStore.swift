import Foundation
import CoreLocation

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

    var selectedTab: Int = 0
    var cloudSync: CloudSyncService?
    var analytics: AnalyticsService?

    private let vineyardsKey = "vinetrack_vineyards"
    private let selectedVineyardIdKey = "vinetrack_selected_vineyard_id"
    private let pinsKey = "vinetrack_pins"
    private let paddocksKey = "vinetrack_paddocks"
    private let tripsKey = "vinetrack_trips"
    private let repairButtonsKey = "vinetrack_repair_buttons"
    private let growthButtonsKey = "vinetrack_growth_buttons"
    private let settingsKey = "vinetrack_settings_v2"
    private let customPatternsKey = "vinetrack_custom_patterns"
    private let sprayRecordsKey = "vinetrack_spray_records"
    private let savedChemicalsKey = "vinetrack_saved_chemicals"
    private let savedSprayPresetsKey = "vinetrack_saved_spray_presets"
    private let savedEquipmentOptionsKey = "vinetrack_saved_equipment_options"
    private let sprayEquipmentKey = "vinetrack_spray_equipment"
    private let tractorsKey = "vinetrack_tractors"
    private let fuelPurchasesKey = "vinetrack_fuel_purchases"
    private let operatorCategoriesKey = "vinetrack_operator_categories"
    private let buttonTemplatesKey = "vinetrack_button_templates"

    private static let storageDirectory: URL = {
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
        pins.removeAll { $0.id == pin.id }
        saveAllPins()
    }

    func deletePins(at offsets: IndexSet, from filteredPins: [VinePin]) {
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
        paddocks.removeAll { $0.id == paddock.id }
        saveAllPaddocks()
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
        trips.removeAll { $0.id == trip.id }
        saveAllTrips()
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
        sprayRecords.removeAll { $0.id == record.id }
        saveAllSprayRecords()
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

    private func assignDefaultOperatorCategory(_ categoryId: UUID, vineyardId: UUID) {
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
        buttonTemplates.removeAll { $0.id == template.id }
        saveAllButtonTemplates()
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
        guard let vid = selectedVineyardId,
              let index = vineyards.firstIndex(where: { $0.id == vid }) else { return }
        vineyards[index].logoData = logoData
        save(vineyards, key: vineyardsKey)
        syncVineyardToCloud(vineyards[index])
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        var allSettings: [AppSettings] = loadData(key: settingsKey) ?? []
        if let index = allSettings.firstIndex(where: { $0.vineyardId == newSettings.vineyardId }) {
            allSettings[index] = newSettings
        } else {
            allSettings.append(newSettings)
        }
        save(allSettings, key: settingsKey)
        syncDataToCloud(dataType: "settings")
    }

    // MARK: - Delete All Data

    func deleteAllPins() {
        pins = []
        saveAllPins()
    }

    func deleteAllTrips() {
        trips = []
        saveAllTrips()
    }

    func deleteAllData() {
        let keys = [pinsKey, paddocksKey, tripsKey, repairButtonsKey, growthButtonsKey, settingsKey, vineyardsKey, customPatternsKey, sprayRecordsKey, savedChemicalsKey, savedSprayPresetsKey, savedEquipmentOptionsKey, sprayEquipmentKey, tractorsKey, fuelPurchasesKey, operatorCategoriesKey, buttonTemplatesKey]
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
    }

    // MARK: - Demo Data

    private func makeDemoRows(range: ClosedRange<Int>, reversed: Bool, startLat: Double, startLon: Double, endLat: Double, endLon: Double, maxN: Int, latStep: Double = 0.000005, lonStep: Double = 0.00003) -> [PaddockRow] {
        let numbers: [Int] = reversed ? Array(range.reversed()) : Array(range)
        return numbers.map { n -> PaddockRow in
            let offset = Double(maxN - n)
            let sLat = startLat + offset * latStep
            let sLon = startLon + offset * lonStep
            let eLat = endLat + offset * latStep
            let eLon = endLon + offset * lonStep
            return PaddockRow(number: n,
                              startPoint: CoordinatePoint(latitude: sLat, longitude: sLon),
                              endPoint: CoordinatePoint(latitude: eLat, longitude: eLon))
        }
    }

    func loadDemoData() {
        clearInMemoryState()

        let demoVineyardId = UUID()
        let demoVineyard = Vineyard(
            id: demoVineyardId,
            name: "Demo Vineyard",
            users: [VineyardUser(name: "Demo User", role: .owner)]
        )
        vineyards.append(demoVineyard)
        save(vineyards, key: vineyardsKey)
        selectedVineyardId = demoVineyard.id

        let pHouse = Paddock(
            id: UUID(uuidString: "66AA78AC-AE8D-466C-97BF-E11190E037D6")!,
            vineyardId: demoVineyardId,
            name: "House",
            polygonPoints: [
                CoordinatePoint(latitude: -33.293789934927624, longitude: 148.95383582182913),
                CoordinatePoint(latitude: -33.294139177410614, longitude: 148.95382125295797),
                CoordinatePoint(latitude: -33.2941399247259, longitude: 148.9540872369286),
                CoordinatePoint(latitude: -33.29380400586172, longitude: 148.9541078003952)
            ],
            rows: Array((110...118).reversed()).map { n in
                PaddockRow(number: n, startPoint: CoordinatePoint(latitude: 0, longitude: 0), endPoint: CoordinatePoint(latitude: 0, longitude: 0))
            },
            rowDirection: 3.5,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0
        )

        let pGruner = Paddock(
            id: UUID(uuidString: "715EE7B8-B5FC-4A4B-A9E9-F8A30F9D62D4")!,
            vineyardId: demoVineyardId,
            name: "Gruner Veltliner",
            polygonPoints: [
                CoordinatePoint(latitude: -33.294464676583765, longitude: 148.95837345152177),
                CoordinatePoint(latitude: -33.29664988172094, longitude: 148.95795121109902),
                CoordinatePoint(latitude: -33.296608195417214, longitude: 148.95752566738577),
                CoordinatePoint(latitude: -33.29438935193399, longitude: 148.95795074805932)
            ],
            rows: makeDemoRows(range: 1...14, reversed: true, startLat: -33.29661, startLon: 148.95754, endLat: -33.29439, endLon: 148.95796, maxN: 14),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: -0.5,
            vineSpacing: 1.0
        )

        let pShiraz = Paddock(
            id: UUID(uuidString: "486E424E-764E-4E1F-B324-283F33B70BD9")!,
            vineyardId: demoVineyardId,
            name: "Shiraz",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29438360651768, longitude: 148.9579585581722),
                CoordinatePoint(latitude: -33.296603412938985, longitude: 148.95752954988978),
                CoordinatePoint(latitude: -33.29654060083049, longitude: 148.95706240946168),
                CoordinatePoint(latitude: -33.29432258764576, longitude: 148.95748959741272)
            ],
            rows: makeDemoRows(range: 15...30, reversed: true, startLat: -33.29654, startLon: 148.95708, endLat: -33.29432, endLon: 148.95750, maxN: 30, latStep: 0.000004),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0
        )

        let pPinotNoir = Paddock(
            id: UUID(uuidString: "A8E82521-257A-49EB-B72E-F892809A2C7B")!,
            vineyardId: demoVineyardId,
            name: "Pinot Noir",
            polygonPoints: [
                CoordinatePoint(latitude: -33.294229405046124, longitude: 148.95446730678736),
                CoordinatePoint(latitude: -33.29495409230544, longitude: 148.95433409128623),
                CoordinatePoint(latitude: -33.29494549825952, longitude: 148.95427642417317),
                CoordinatePoint(latitude: -33.29593531449693, longitude: 148.95408524804103),
                CoordinatePoint(latitude: -33.296163630981184, longitude: 148.9542515439016),
                CoordinatePoint(latitude: -33.296296242739274, longitude: 148.95524552622425),
                CoordinatePoint(latitude: -33.295924088135635, longitude: 148.95531660429367),
                CoordinatePoint(latitude: -33.295625167625566, longitude: 148.95520439929098),
                CoordinatePoint(latitude: -33.29538341491391, longitude: 148.9551856239519),
                CoordinatePoint(latitude: -33.295078777022646, longitude: 148.95513376825343),
                CoordinatePoint(latitude: -33.29486088783918, longitude: 148.95510413436787),
                CoordinatePoint(latitude: -33.2948474831947, longitude: 148.95503745723542),
                CoordinatePoint(latitude: -33.29431946071445, longitude: 148.95513810879112)
            ],
            rows: makeDemoRows(range: 69...108, reversed: true, startLat: -33.29596, startLon: 148.95410, endLat: -33.29423, endLon: 148.95449, maxN: 108),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0
        )

        let pPrimitivo = Paddock(
            id: UUID(uuidString: "DF0E740B-D65F-4E79-9806-6E3F736B137B")!,
            vineyardId: demoVineyardId,
            name: "Primitivo",
            polygonPoints: [
                CoordinatePoint(latitude: -33.296539731656615, longitude: 148.95706294094194),
                CoordinatePoint(latitude: -33.296509092364175, longitude: 148.95685372863093),
                CoordinatePoint(latitude: -33.294278092587696, longitude: 148.95728159478563),
                CoordinatePoint(latitude: -33.29431668518322, longitude: 148.95749014641655)
            ],
            rows: makeDemoRows(range: 31...37, reversed: true, startLat: -33.29651, startLon: 148.95685, endLat: -33.29428, endLon: 148.95728, maxN: 37),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0
        )

        let pCabFranc = Paddock(
            id: UUID(uuidString: "3AB9BF77-3AE1-4C01-A6CC-850DA38B1A5B")!,
            vineyardId: demoVineyardId,
            name: "Cab Franc",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29650967737192, longitude: 148.9568523414743),
                CoordinatePoint(latitude: -33.29647716981803, longitude: 148.95664692895718),
                CoordinatePoint(latitude: -33.294261184967056, longitude: 148.95707340784196),
                CoordinatePoint(latitude: -33.2942874534165, longitude: 148.9572790520895)
            ],
            rows: makeDemoRows(range: 38...44, reversed: true, startLat: -33.29648, startLon: 148.95665, endLat: -33.29426, endLon: 148.95707, maxN: 44),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0
        )

        let pSauvBlanc = Paddock(
            id: UUID(uuidString: "DC32EC37-DE50-4620-83B7-CCED1DC65D75")!,
            vineyardId: demoVineyardId,
            name: "Sauv Blanc",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29637534029164, longitude: 148.9559306832998),
                CoordinatePoint(latitude: -33.29588130528306, longitude: 148.95602096414402),
                CoordinatePoint(latitude: -33.29569146808536, longitude: 148.9561713714582),
                CoordinatePoint(latitude: -33.29551093354972, longitude: 148.95621729074338),
                CoordinatePoint(latitude: -33.29548355655761, longitude: 148.95629917438146),
                CoordinatePoint(latitude: -33.295148187706985, longitude: 148.95632718720495),
                CoordinatePoint(latitude: -33.29420277634263, longitude: 148.9565775666412),
                CoordinatePoint(latitude: -33.29421754572732, longitude: 148.9566887560023),
                CoordinatePoint(latitude: -33.29643727927688, longitude: 148.95626231061016)
            ],
            rows: makeDemoRows(range: 58...68, reversed: true, startLat: -33.29644, startLon: 148.95593, endLat: -33.29420, endLon: 148.95626, maxN: 68),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0.5,
            vineSpacing: 1.0
        )

        let pMerlot = Paddock(
            id: UUID(uuidString: "43F9BB12-FD3A-45CF-8AE8-22A2D00D688C")!,
            vineyardId: demoVineyardId,
            name: "Merlot",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29425949643701, longitude: 148.95707409583076),
                CoordinatePoint(latitude: -33.2942328331289, longitude: 148.95686330035971),
                CoordinatePoint(latitude: -33.29644934950337, longitude: 148.95644128457215),
                CoordinatePoint(latitude: -33.29647710607891, longitude: 148.95664715973072)
            ],
            rows: makeDemoRows(range: 45...51, reversed: true, startLat: -33.29645, startLon: 148.95644, endLat: -33.29423, endLon: 148.95686, maxN: 51),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0
        )

        let pPinotGris = Paddock(
            id: UUID(uuidString: "1ABF325F-3EEC-4CAD-912C-12BC2E371928")!,
            vineyardId: demoVineyardId,
            name: "Pinot Gris",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29423498464803, longitude: 148.95686152287013),
                CoordinatePoint(latitude: -33.29421589608211, longitude: 148.95668903200138),
                CoordinatePoint(latitude: -33.2964296646789, longitude: 148.95626403176502),
                CoordinatePoint(latitude: -33.29645708811178, longitude: 148.9564381911035)
            ],
            rows: makeDemoRows(range: 52...57, reversed: false, startLat: -33.29643, startLon: 148.95626, endLat: -33.29422, endLon: 148.95669, maxN: 57),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0
        )

        paddocks = [pShiraz, pPinotNoir, pGruner, pHouse, pPrimitivo, pCabFranc, pSauvBlanc, pMerlot, pPinotGris]
        var allPaddocks: [Paddock] = loadData(key: paddocksKey) ?? []
        allPaddocks.append(contentsOf: paddocks)
        save(allPaddocks, key: paddocksKey)

        let equip1 = SprayEquipmentItem(vineyardId: demoVineyardId, name: "1500L Croplands QM-420", tankCapacityLitres: 1500)
        let equip2 = SprayEquipmentItem(vineyardId: demoVineyardId, name: "200L Silvan UTE Sprayer", tankCapacityLitres: 200)
        sprayEquipment = [equip1, equip2]
        var allEquip: [SprayEquipmentItem] = loadData(key: sprayEquipmentKey) ?? []
        allEquip.append(contentsOf: sprayEquipment)
        save(allEquip, key: sprayEquipmentKey)

        let tractor1 = Tractor(vineyardId: demoVineyardId, name: "John Deere 5075E", brand: "John Deere", model: "5075E", fuelUsageLPerHour: 8.5)
        let tractor2 = Tractor(vineyardId: demoVineyardId, name: "Kubota M7060", brand: "Kubota", model: "M7060", fuelUsageLPerHour: 7.2)
        tractors = [tractor1, tractor2]
        var allTractors: [Tractor] = loadData(key: tractorsKey) ?? []
        allTractors.append(contentsOf: tractors)
        save(allTractors, key: tractorsKey)

        let fp1 = FuelPurchase(vineyardId: demoVineyardId, volumeLitres: 500, totalCost: 950, date: Calendar.current.date(byAdding: .day, value: -30, to: Date())!)
        let fp2 = FuelPurchase(vineyardId: demoVineyardId, volumeLitres: 300, totalCost: 585, date: Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
        fuelPurchases = [fp1, fp2]
        var allFuel: [FuelPurchase] = loadData(key: fuelPurchasesKey) ?? []
        allFuel.append(contentsOf: fuelPurchases)
        save(allFuel, key: fuelPurchasesKey)

        let mancozebLowRate = ChemicalRate(label: "Low", value: ChemicalUnit.grams.toBase(200), basis: .perHectare)
        let mancozebHighRate = ChemicalRate(label: "High", value: ChemicalUnit.grams.toBase(300), basis: .perHectare)
        let mancozeb = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Mancozeb 750 WG",
            unit: .grams,
            chemicalGroup: "M3 — Dithiocarbamate",
            use: "Downy Mildew preventative",
            manufacturer: "Nufarm",
            activeIngredient: "Mancozeb 750g/kg",
            rates: [mancozebLowRate, mancozebHighRate],
            purchase: ChemicalPurchase(brand: "Nufarm", activeIngredient: "Mancozeb 750g/kg", costDollars: 42, containerSizeML: 10, containerUnit: .kilograms)
        )

        let copperLowRate = ChemicalRate(label: "Low", value: ChemicalUnit.millilitres.toBase(150), basis: .per100Litres)
        let copperHighRate = ChemicalRate(label: "High", value: ChemicalUnit.millilitres.toBase(250), basis: .per100Litres)
        let copperOxychloride = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Copper Oxychloride 500 SC",
            unit: .millilitres,
            chemicalGroup: "M1 — Copper",
            use: "Downy Mildew protectant",
            manufacturer: "BASF",
            activeIngredient: "Copper Oxychloride 500g/L",
            rates: [copperLowRate, copperHighRate],
            purchase: ChemicalPurchase(brand: "BASF", activeIngredient: "Copper Oxychloride 500g/L", costDollars: 85, containerSizeML: 20, containerUnit: .litres)
        )

        let sulphurHaRate = ChemicalRate(label: "Standard", value: ChemicalUnit.kilograms.toBase(3), basis: .perHectare)
        let sulphur = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Wettable Sulphur 800 WG",
            unit: .kilograms,
            chemicalGroup: "M2 — Inorganic (Sulphur)",
            use: "Powdery Mildew preventative",
            manufacturer: "Bayer",
            activeIngredient: "Sulphur 800g/kg",
            rates: [sulphurHaRate],
            purchase: ChemicalPurchase(brand: "Bayer", activeIngredient: "Sulphur 800g/kg", costDollars: 28, containerSizeML: 15, containerUnit: .kilograms)
        )

        let trifloxystrobinRate = ChemicalRate(label: "Standard", value: ChemicalUnit.millilitres.toBase(150), basis: .perHectare)
        let trifloxystrobin = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Flint 500 WG",
            unit: .millilitres,
            chemicalGroup: "11 — Strobilurin",
            use: "Powdery Mildew curative",
            manufacturer: "Bayer",
            activeIngredient: "Trifloxystrobin 500g/kg",
            rates: [trifloxystrobinRate],
            purchase: ChemicalPurchase(brand: "Bayer", activeIngredient: "Trifloxystrobin 500g/kg", costDollars: 195, containerSizeML: 1, containerUnit: .kilograms)
        )

        let phosphonateRate100L = ChemicalRate(label: "Standard", value: ChemicalUnit.millilitres.toBase(500), basis: .per100Litres)
        let phosphonate = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Agri-Fos 600",
            unit: .litres,
            chemicalGroup: "33 — Phosphonate",
            use: "Downy Mildew systemic",
            manufacturer: "AgNova",
            activeIngredient: "Phosphorous Acid 600g/L",
            rates: [phosphonateRate100L],
            purchase: ChemicalPurchase(brand: "AgNova", activeIngredient: "Phosphorous Acid 600g/L", costDollars: 65, containerSizeML: 20, containerUnit: .litres)
        )

        savedChemicals = [mancozeb, copperOxychloride, sulphur, trifloxystrobin, phosphonate]
        var allChemicals: [SavedChemical] = loadData(key: savedChemicalsKey) ?? []
        allChemicals.append(contentsOf: savedChemicals)
        save(allChemicals, key: savedChemicalsKey)

        let cal = Calendar.current
        let now = Date()

        let baseLat = -33.29546
        let baseLon = 148.95751

        func generatePath(startLat: Double, startLon: Double, rows: Int, rowSpacing: Double) -> [CoordinatePoint] {
            var points: [CoordinatePoint] = []
            let rowLengthDeg = 0.002
            let rowSpacingDeg = rowSpacing / 111320.0
            let angleDeg = 9.0
            let angleRad = angleDeg * .pi / 180.0
            let cosA = cos(angleRad)
            let sinA = sin(angleRad)
            let cosLat = cos(startLat * .pi / 180.0)
            for r in 0..<rows {
                let perpLat = Double(r) * rowSpacingDeg * (-sinA)
                let perpLon = Double(r) * rowSpacingDeg * cosA / cosLat
                let rowBaseLat = startLat + perpLat
                let rowBaseLon = startLon + perpLon
                let dLat = rowLengthDeg * cosA
                let dLon = rowLengthDeg * sinA / cosLat
                if r % 2 == 0 {
                    points.append(CoordinatePoint(latitude: rowBaseLat, longitude: rowBaseLon))
                    points.append(CoordinatePoint(latitude: rowBaseLat + dLat, longitude: rowBaseLon + dLon))
                } else {
                    points.append(CoordinatePoint(latitude: rowBaseLat + dLat, longitude: rowBaseLon + dLon))
                    points.append(CoordinatePoint(latitude: rowBaseLat, longitude: rowBaseLon))
                }
            }
            return points
        }

        let trip1Id = UUID()
        let trip1Start = cal.date(byAdding: .day, value: -21, to: now)!
        let trip1End = cal.date(byAdding: .hour, value: 3, to: trip1Start)!
        let trip1Seq = TrackingPattern.sequential.generateSequence(startRow: 15, totalRows: 16)
        let trip1 = Trip(
            id: trip1Id,
            vineyardId: demoVineyardId,
            paddockId: pShiraz.id,
            paddockName: pShiraz.name,
            paddockIds: [pShiraz.id],
            startTime: trip1Start,
            endTime: trip1End,
            currentRowNumber: 30.5,
            nextRowNumber: 31.5,
            pathPoints: generatePath(startLat: -33.29654, startLon: 148.95708, rows: 16, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: trip1Seq,
            sequenceIndex: trip1Seq.count,
            personName: "Demo User",
            totalDistance: 4200,
            completedPaths: trip1Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip1Start, endTime: cal.date(byAdding: .hour, value: 1, to: trip1Start), pathsCovered: Array(trip1Seq.prefix(6)), startRow: 14.5, endRow: 19.5),
                TankSession(tankNumber: 2, startTime: cal.date(byAdding: .hour, value: 1, to: trip1Start)!, endTime: cal.date(byAdding: .hour, value: 2, to: trip1Start), pathsCovered: Array(trip1Seq.dropFirst(6).prefix(5)), startRow: 20.5, endRow: 24.5),
                TankSession(tankNumber: 3, startTime: cal.date(byAdding: .hour, value: 2, to: trip1Start)!, endTime: trip1End, pathsCovered: Array(trip1Seq.suffix(5)), startRow: 25.5, endRow: 30.5)
            ],
            totalTanks: 3
        )

        let trip2Id = UUID()
        let trip2Start = cal.date(byAdding: .day, value: -14, to: now)!
        let trip2End = cal.date(byAdding: .hour, value: 2, to: trip2Start)!
        let trip2Seq = TrackingPattern.everySecondRow.generateSequence(startRow: 1, totalRows: 14)
        let trip2 = Trip(
            id: trip2Id,
            vineyardId: demoVineyardId,
            paddockId: pGruner.id,
            paddockName: pGruner.name,
            paddockIds: [pGruner.id],
            startTime: trip2Start,
            endTime: trip2End,
            currentRowNumber: 14.5,
            nextRowNumber: 15.5,
            pathPoints: generatePath(startLat: -33.29661, startLon: 148.95754, rows: 14, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .everySecondRow,
            rowSequence: trip2Seq,
            sequenceIndex: trip2Seq.count,
            personName: "Demo User",
            totalDistance: 3150,
            completedPaths: trip2Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip2Start, endTime: cal.date(byAdding: .hour, value: 1, to: trip2Start), pathsCovered: Array(trip2Seq.prefix(7)), startRow: 0.5, endRow: 13.5),
                TankSession(tankNumber: 2, startTime: cal.date(byAdding: .hour, value: 1, to: trip2Start)!, endTime: trip2End, pathsCovered: Array(trip2Seq.suffix(7)), startRow: 12.5, endRow: 1.5)
            ],
            totalTanks: 2
        )

        let trip3Id = UUID()
        let trip3Start = cal.date(byAdding: .day, value: -7, to: now)!
        let trip3End = cal.date(byAdding: .minute, value: 90, to: trip3Start)!
        let trip3Seq = TrackingPattern.sequential.generateSequence(startRow: 31, totalRows: 7)
        let trip3 = Trip(
            id: trip3Id,
            vineyardId: demoVineyardId,
            paddockId: pPrimitivo.id,
            paddockName: pPrimitivo.name,
            paddockIds: [pPrimitivo.id],
            startTime: trip3Start,
            endTime: trip3End,
            currentRowNumber: 37.5,
            nextRowNumber: 38.5,
            pathPoints: generatePath(startLat: -33.29651, startLon: 148.95685, rows: 7, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: trip3Seq,
            sequenceIndex: trip3Seq.count,
            personName: "Demo User",
            totalDistance: 2100,
            completedPaths: trip3Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip3Start, endTime: trip3End, pathsCovered: trip3Seq, startRow: 30.5, endRow: 37.5)
            ],
            totalTanks: 1
        )

        let trip4Id = UUID()
        let trip4Start = cal.date(byAdding: .day, value: -3, to: now)!
        let trip4End = cal.date(byAdding: .hour, value: 4, to: trip4Start)!
        let trip4Seq = TrackingPattern.sequential.generateSequence(startRow: 15, totalRows: 16)
        let trip4 = Trip(
            id: trip4Id,
            vineyardId: demoVineyardId,
            paddockId: pShiraz.id,
            paddockName: "\(pShiraz.name), \(pPinotNoir.name)",
            paddockIds: [pShiraz.id, pPinotNoir.id],
            startTime: trip4Start,
            endTime: trip4End,
            currentRowNumber: 30.5,
            nextRowNumber: 31.5,
            pathPoints: generatePath(startLat: -33.29654, startLon: 148.95708, rows: 16, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: trip4Seq,
            sequenceIndex: trip4Seq.count,
            personName: "Demo User",
            totalDistance: 5600,
            completedPaths: trip4Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip4Start, endTime: cal.date(byAdding: .hour, value: 2, to: trip4Start), pathsCovered: Array(trip4Seq.prefix(8)), startRow: 14.5, endRow: 21.5),
                TankSession(tankNumber: 2, startTime: cal.date(byAdding: .hour, value: 2, to: trip4Start)!, endTime: trip4End, pathsCovered: Array(trip4Seq.suffix(8)), startRow: 22.5, endRow: 30.5)
            ],
            totalTanks: 2
        )

        let trip5Id = UUID()
        let trip5 = Trip(
            id: trip5Id,
            vineyardId: demoVineyardId,
            paddockId: pSauvBlanc.id,
            paddockName: pSauvBlanc.name,
            paddockIds: [pSauvBlanc.id],
            startTime: now,
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: TrackingPattern.sequential.generateSequence(startRow: 58, totalRows: 11),
            personName: "Demo User"
        )

        trips = [trip1, trip2, trip3, trip4, trip5]
        var allTrips: [Trip] = loadData(key: tripsKey) ?? []
        allTrips.append(contentsOf: trips)
        save(allTrips, key: tripsKey)

        let mancozebCostPerBase = mancozeb.purchase?.costPerBaseUnit ?? 0
        let copperCostPerBase = copperOxychloride.purchase?.costPerBaseUnit ?? 0
        let sulphurCostPerBase = sulphur.purchase?.costPerBaseUnit ?? 0
        let trifloxyCostPerBase = trifloxystrobin.purchase?.costPerBaseUnit ?? 0
        let phosphonateCostPerBase = phosphonate.purchase?.costPerBaseUnit ?? 0

        let sprayRecord1 = SprayRecord(
            tripId: trip1Id,
            vineyardId: demoVineyardId,
            date: trip1Start,
            startTime: trip1Start,
            endTime: trip1End,
            temperature: 18.5,
            windSpeed: 12.0,
            windDirection: "NW",
            humidity: 65,
            sprayReference: "Downy Mildew Prevention — Spray 1",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Copper Oxychloride 500 SC", volumePerTank: ChemicalUnit.millilitres.toBase(2250), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: copperCostPerBase, unit: .millilitres)
                ]),
                SprayTank(tankNumber: 2, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Copper Oxychloride 500 SC", volumePerTank: ChemicalUnit.millilitres.toBase(2250), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: copperCostPerBase, unit: .millilitres)
                ]),
                SprayTank(tankNumber: 3, waterVolume: 1000, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(400), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Copper Oxychloride 500 SC", volumePerTank: ChemicalUnit.millilitres.toBase(1500), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: copperCostPerBase, unit: .millilitres)
                ])
            ],
            notes: "Good conditions, light NW breeze. Full coverage on Shiraz block.",
            numberOfFansJets: "6",
            averageSpeed: 5.2,
            equipmentType: "1500L Croplands QM-420",
            tractor: "John Deere 5075E",
            tractorGear: "2L"
        )

        let sprayRecord2 = SprayRecord(
            tripId: trip2Id,
            vineyardId: demoVineyardId,
            date: trip2Start,
            startTime: trip2Start,
            endTime: trip2End,
            temperature: 22.0,
            windSpeed: 8.5,
            windDirection: "SE",
            humidity: 55,
            sprayReference: "Powdery Mildew Control — Spray 1",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 1500, sprayRatePerHa: 700, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(4.5), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms),
                    SprayChemical(name: "Flint 500 WG", volumePerTank: ChemicalUnit.millilitres.toBase(321), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: trifloxyCostPerBase, unit: .millilitres)
                ]),
                SprayTank(tankNumber: 2, waterVolume: 1200, sprayRatePerHa: 700, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(3.6), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms),
                    SprayChemical(name: "Flint 500 WG", volumePerTank: ChemicalUnit.millilitres.toBase(257), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: trifloxyCostPerBase, unit: .millilitres)
                ])
            ],
            notes: "Warm day, applied early morning on Gruner Veltliner.",
            numberOfFansJets: "6",
            averageSpeed: 4.8,
            equipmentType: "1500L Croplands QM-420",
            tractor: "Kubota M7060",
            tractorGear: "2L"
        )

        let sprayRecord3 = SprayRecord(
            tripId: trip3Id,
            vineyardId: demoVineyardId,
            date: trip3Start,
            startTime: trip3Start,
            endTime: trip3End,
            temperature: 16.0,
            windSpeed: 5.0,
            windDirection: "N",
            humidity: 72,
            sprayReference: "Downy Mildew Systemic — Spray 2",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 800, sprayRatePerHa: 600, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Agri-Fos 600", volumePerTank: ChemicalUnit.millilitres.toBase(4000), ratePerHa: ChemicalUnit.millilitres.toBase(500), costPerUnit: phosphonateCostPerBase, unit: .litres)
                ])
            ],
            notes: "Primitivo block, single tank coverage. Cool conditions.",
            numberOfFansJets: "4",
            averageSpeed: 4.5,
            equipmentType: "1500L Croplands QM-420",
            tractor: "John Deere 5075E",
            tractorGear: "1H"
        )

        let sprayRecord4 = SprayRecord(
            tripId: trip4Id,
            vineyardId: demoVineyardId,
            date: trip4Start,
            startTime: trip4Start,
            endTime: trip4End,
            temperature: 20.0,
            windSpeed: 10.0,
            windDirection: "SW",
            humidity: 60,
            sprayReference: "Season Protection — Spray 3",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(5.6), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms)
                ]),
                SprayTank(tankNumber: 2, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(5.6), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms)
                ])
            ],
            notes: "Multi-block spray covering Shiraz and Pinot Noir. Moderate SW wind.",
            numberOfFansJets: "6",
            averageSpeed: 5.0,
            equipmentType: "1500L Croplands QM-420",
            tractor: "John Deere 5075E",
            tractorGear: "2L"
        )

        let sprayRecord5 = SprayRecord(
            tripId: trip5Id,
            vineyardId: demoVineyardId,
            date: now,
            startTime: now,
            sprayReference: "Powdery Mildew Prevention — Spray 2",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 800, sprayRatePerHa: 600, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(3), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms)
                ])
            ],
            equipmentType: "1500L Croplands QM-420",
            tractor: "Kubota M7060",
            tractorGear: "2L"
        )

        sprayRecords = [sprayRecord1, sprayRecord2, sprayRecord3, sprayRecord4, sprayRecord5]
        var allSprayRecords: [SprayRecord] = loadData(key: sprayRecordsKey) ?? []
        allSprayRecords.append(contentsOf: sprayRecords)
        save(allSprayRecords, key: sprayRecordsKey)
    }

    // MARK: - Computed

    var activeTrip: Trip? {
        trips.first { $0.isActive }
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

    // MARK: - Cloud Merge Helpers

    func mergeVineyards(_ remote: [Vineyard]) {
        for rv in remote {
            if !vineyards.contains(where: { $0.id == rv.id }) {
                vineyards.append(rv)
            }
        }
        save(vineyards, key: vineyardsKey)
        if selectedVineyardId == nil, let first = vineyards.first {
            selectedVineyardId = first.id
        }
    }

    func mergePins(_ remote: [VinePin], for vineyardId: UUID) {
        var all: [VinePin] = loadData(key: pinsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: pinsKey)
        if selectedVineyardId == vineyardId {
            pins = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func mergePaddocks(_ remote: [Paddock], for vineyardId: UUID) {
        var all: [Paddock] = loadData(key: paddocksKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: paddocksKey)
        if selectedVineyardId == vineyardId {
            paddocks = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func mergeTrips(_ remote: [Trip], for vineyardId: UUID) {
        var all: [Trip] = loadData(key: tripsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: tripsKey)
        if selectedVineyardId == vineyardId {
            trips = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func mergeRepairButtons(_ remote: [ButtonConfig], for vineyardId: UUID) {
        var all: [ButtonConfig] = loadData(key: repairButtonsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: repairButtonsKey)
        if selectedVineyardId == vineyardId {
            repairButtons = remote
        }
    }

    func mergeGrowthButtons(_ remote: [ButtonConfig], for vineyardId: UUID) {
        var all: [ButtonConfig] = loadData(key: growthButtonsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: growthButtonsKey)
        if selectedVineyardId == vineyardId {
            growthButtons = remote
        }
    }

    func mergeSettings(_ remote: [AppSettings], for vineyardId: UUID) {
        var all: [AppSettings] = loadData(key: settingsKey) ?? []
        for item in remote {
            if let index = all.firstIndex(where: { $0.vineyardId == item.vineyardId }) {
                all[index] = item
            } else {
                all.append(item)
            }
        }
        save(all, key: settingsKey)
        if selectedVineyardId == vineyardId, let s = remote.first {
            settings = s
        }
    }

    func mergeCustomPatterns(_ remote: [SavedCustomPattern], for vineyardId: UUID) {
        var all: [SavedCustomPattern] = loadData(key: customPatternsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: customPatternsKey)
        if selectedVineyardId == vineyardId {
            savedCustomPatterns = all.filter { $0.vineyardId == vineyardId }
        }
    }

    // MARK: - Replace Helpers (timestamp-based conflict resolution)

    func replacePins(_ remote: [VinePin], for vineyardId: UUID) {
        var all: [VinePin] = loadData(key: pinsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: pinsKey)
        if selectedVineyardId == vineyardId {
            pins = remote
        }
    }

    func replacePaddocks(_ remote: [Paddock], for vineyardId: UUID) {
        var all: [Paddock] = loadData(key: paddocksKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: paddocksKey)
        if selectedVineyardId == vineyardId {
            paddocks = remote
        }
    }

    func replaceTrips(_ remote: [Trip], for vineyardId: UUID) {
        var all: [Trip] = loadData(key: tripsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: tripsKey)
        if selectedVineyardId == vineyardId {
            trips = remote
        }
    }

    func replaceCustomPatterns(_ remote: [SavedCustomPattern], for vineyardId: UUID) {
        var all: [SavedCustomPattern] = loadData(key: customPatternsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: customPatternsKey)
        if selectedVineyardId == vineyardId {
            savedCustomPatterns = remote
        }
    }

    func mergeSavedChemicals(_ remote: [SavedChemical], for vineyardId: UUID) {
        var all: [SavedChemical] = loadData(key: savedChemicalsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: savedChemicalsKey)
        if selectedVineyardId == vineyardId {
            savedChemicals = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceSavedChemicals(_ remote: [SavedChemical], for vineyardId: UUID) {
        var all: [SavedChemical] = loadData(key: savedChemicalsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: savedChemicalsKey)
        if selectedVineyardId == vineyardId {
            savedChemicals = remote
        }
    }

    func mergeSavedSprayPresets(_ remote: [SavedSprayPreset], for vineyardId: UUID) {
        var all: [SavedSprayPreset] = loadData(key: savedSprayPresetsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: savedSprayPresetsKey)
        if selectedVineyardId == vineyardId {
            savedSprayPresets = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceSavedSprayPresets(_ remote: [SavedSprayPreset], for vineyardId: UUID) {
        var all: [SavedSprayPreset] = loadData(key: savedSprayPresetsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: savedSprayPresetsKey)
        if selectedVineyardId == vineyardId {
            savedSprayPresets = remote
        }
    }

    func mergeSavedEquipmentOptions(_ remote: [SavedEquipmentOption], for vineyardId: UUID) {
        var all: [SavedEquipmentOption] = loadData(key: savedEquipmentOptionsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: savedEquipmentOptionsKey)
        if selectedVineyardId == vineyardId {
            savedEquipmentOptions = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceSavedEquipmentOptions(_ remote: [SavedEquipmentOption], for vineyardId: UUID) {
        var all: [SavedEquipmentOption] = loadData(key: savedEquipmentOptionsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: savedEquipmentOptionsKey)
        if selectedVineyardId == vineyardId {
            savedEquipmentOptions = remote
        }
    }

    func mergeSprayEquipment(_ remote: [SprayEquipmentItem], for vineyardId: UUID) {
        var all: [SprayEquipmentItem] = loadData(key: sprayEquipmentKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: sprayEquipmentKey)
        if selectedVineyardId == vineyardId {
            sprayEquipment = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceSprayEquipment(_ remote: [SprayEquipmentItem], for vineyardId: UUID) {
        var all: [SprayEquipmentItem] = loadData(key: sprayEquipmentKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: sprayEquipmentKey)
        if selectedVineyardId == vineyardId {
            sprayEquipment = remote
        }
    }

    func mergeTractors(_ remote: [Tractor], for vineyardId: UUID) {
        var all: [Tractor] = loadData(key: tractorsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: tractorsKey)
        if selectedVineyardId == vineyardId {
            tractors = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceTractors(_ remote: [Tractor], for vineyardId: UUID) {
        var all: [Tractor] = loadData(key: tractorsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: tractorsKey)
        if selectedVineyardId == vineyardId {
            tractors = remote
        }
    }

    func mergeFuelPurchases(_ remote: [FuelPurchase], for vineyardId: UUID) {
        var all: [FuelPurchase] = loadData(key: fuelPurchasesKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: fuelPurchasesKey)
        if selectedVineyardId == vineyardId {
            fuelPurchases = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceFuelPurchases(_ remote: [FuelPurchase], for vineyardId: UUID) {
        var all: [FuelPurchase] = loadData(key: fuelPurchasesKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: fuelPurchasesKey)
        if selectedVineyardId == vineyardId {
            fuelPurchases = remote
        }
    }

    func replaceSprayRecords(_ remote: [SprayRecord], for vineyardId: UUID) {
        var all: [SprayRecord] = loadData(key: sprayRecordsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: sprayRecordsKey)
        if selectedVineyardId == vineyardId {
            sprayRecords = remote
        }
    }

    func mergeSprayRecords(_ remote: [SprayRecord], for vineyardId: UUID) {
        var all: [SprayRecord] = loadData(key: sprayRecordsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: sprayRecordsKey)
        if selectedVineyardId == vineyardId {
            sprayRecords = all.filter { $0.vineyardId == vineyardId }
        }
    }

    // MARK: - Private Save Helpers

    private func saveAllPins() {
        var allPins: [VinePin] = loadData(key: pinsKey) ?? []
        if let vid = selectedVineyardId {
            allPins.removeAll { $0.vineyardId == vid }
        }
        allPins.append(contentsOf: pins)
        save(allPins, key: pinsKey)
        syncDataToCloud(dataType: "pins")
    }

    private func saveAllPaddocks() {
        var allPaddocks: [Paddock] = loadData(key: paddocksKey) ?? []
        if let vid = selectedVineyardId {
            allPaddocks.removeAll { $0.vineyardId == vid }
        }
        allPaddocks.append(contentsOf: paddocks)
        save(allPaddocks, key: paddocksKey)
        syncDataToCloud(dataType: "paddocks")
    }

    private func saveAllTrips() {
        var allTrips: [Trip] = loadData(key: tripsKey) ?? []
        if let vid = selectedVineyardId {
            allTrips.removeAll { $0.vineyardId == vid }
        }
        allTrips.append(contentsOf: trips)
        save(allTrips, key: tripsKey)
        syncDataToCloud(dataType: "trips")
    }

    private func saveAllRepairButtons() {
        var allButtons: [ButtonConfig] = loadData(key: repairButtonsKey) ?? []
        if let vid = selectedVineyardId {
            allButtons.removeAll { $0.vineyardId == vid }
        }
        allButtons.append(contentsOf: repairButtons)
        save(allButtons, key: repairButtonsKey)
        syncDataToCloud(dataType: "repair_buttons")
    }

    private func saveAllGrowthButtons() {
        var allButtons: [ButtonConfig] = loadData(key: growthButtonsKey) ?? []
        if let vid = selectedVineyardId {
            allButtons.removeAll { $0.vineyardId == vid }
        }
        allButtons.append(contentsOf: growthButtons)
        save(allButtons, key: growthButtonsKey)
        syncDataToCloud(dataType: "growth_buttons")
    }

    private func saveAllSprayRecords() {
        var allRecords: [SprayRecord] = loadData(key: sprayRecordsKey) ?? []
        if let vid = selectedVineyardId {
            allRecords.removeAll { $0.vineyardId == vid }
        }
        allRecords.append(contentsOf: sprayRecords)
        save(allRecords, key: sprayRecordsKey)
        syncDataToCloud(dataType: "spray_records")
    }

    private func saveAllSavedChemicals() {
        var all: [SavedChemical] = loadData(key: savedChemicalsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: savedChemicals)
        save(all, key: savedChemicalsKey)
        syncDataToCloud(dataType: "saved_chemicals")
    }

    private func saveAllSavedSprayPresets() {
        var all: [SavedSprayPreset] = loadData(key: savedSprayPresetsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: savedSprayPresets)
        save(all, key: savedSprayPresetsKey)
        syncDataToCloud(dataType: "saved_spray_presets")
    }

    private func saveAllSavedEquipmentOptions() {
        var all: [SavedEquipmentOption] = loadData(key: savedEquipmentOptionsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: savedEquipmentOptions)
        save(all, key: savedEquipmentOptionsKey)
        syncDataToCloud(dataType: "saved_equipment_options")
    }

    private func saveAllSprayEquipment() {
        var all: [SprayEquipmentItem] = loadData(key: sprayEquipmentKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: sprayEquipment)
        save(all, key: sprayEquipmentKey)
        syncDataToCloud(dataType: "spray_equipment")
    }

    private func saveAllTractors() {
        var all: [Tractor] = loadData(key: tractorsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: tractors)
        save(all, key: tractorsKey)
        syncDataToCloud(dataType: "tractors")
    }

    private func saveAllFuelPurchases() {
        var all: [FuelPurchase] = loadData(key: fuelPurchasesKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: fuelPurchases)
        save(all, key: fuelPurchasesKey)
        syncDataToCloud(dataType: "fuel_purchases")
    }

    private func saveAllOperatorCategories() {
        var all: [OperatorCategory] = loadData(key: operatorCategoriesKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: operatorCategories)
        save(all, key: operatorCategoriesKey)
        syncDataToCloud(dataType: "operator_categories")
    }

    private func saveAllButtonTemplates() {
        var all: [ButtonTemplate] = loadData(key: buttonTemplatesKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: buttonTemplates)
        save(all, key: buttonTemplatesKey)
        syncDataToCloud(dataType: "button_templates")
    }

    private func saveAllCustomPatterns() {
        var allPatterns: [SavedCustomPattern] = loadData(key: customPatternsKey) ?? []
        if let vid = selectedVineyardId {
            allPatterns.removeAll { $0.vineyardId == vid }
        }
        allPatterns.append(contentsOf: savedCustomPatterns)
        save(allPatterns, key: customPatternsKey)
        syncDataToCloud(dataType: "custom_patterns")
    }

    private func save<T: Encodable>(_ data: T, key: String) {
        do {
            let encoded = try JSONEncoder().encode(data)
            let fileURL = Self.storageDirectory.appendingPathComponent("\(key).json")
            try encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("DataStore: Failed to save \(key): \(error)")
        }
    }

    private func loadData<T: Decodable>(key: String) -> T? {
        let fileURL = Self.storageDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("DataStore: Failed to decode \(key): \(error)")
            return nil
        }
    }

    // MARK: - Cloud Sync

    private func syncVineyardToCloud(_ vineyard: Vineyard) {
        guard let sync = cloudSync else { return }
        Task { try? await sync.uploadVineyard(vineyard) }
    }

    private func syncDataToCloud(dataType: String) {
        guard let sync = cloudSync, let vid = selectedVineyardId else { return }
        let dataToSync: any Encodable & Sendable = {
            switch dataType {
            case "pins": return pins as [VinePin]
            case "paddocks": return paddocks as [Paddock]
            case "trips": return trips as [Trip]
            case "repair_buttons": return repairButtons as [ButtonConfig]
            case "growth_buttons": return growthButtons as [ButtonConfig]
            case "settings": return [settings] as [AppSettings]
            case "custom_patterns": return savedCustomPatterns as [SavedCustomPattern]
            case "spray_records": return sprayRecords as [SprayRecord]
            case "saved_chemicals": return savedChemicals as [SavedChemical]
            case "saved_spray_presets": return savedSprayPresets as [SavedSprayPreset]
            case "saved_equipment_options": return savedEquipmentOptions as [SavedEquipmentOption]
            case "spray_equipment": return sprayEquipment as [SprayEquipmentItem]
            case "tractors": return tractors as [Tractor]
            case "fuel_purchases": return fuelPurchases as [FuelPurchase]
            case "operator_categories": return operatorCategories as [OperatorCategory]
            default: return [] as [String]
            }
        }()
        Task { await sync.uploadDataForVineyard(vid, dataType: dataType, data: dataToSync) }
    }

    // MARK: - Migration

    private func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "vinetrack_migrated_to_files"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let keys = [vineyardsKey, pinsKey, paddocksKey, tripsKey, repairButtonsKey, growthButtonsKey, settingsKey, customPatternsKey]
        var didMigrate = false

        for key in keys {
            if let data = UserDefaults.standard.data(forKey: key) {
                let fileURL = Self.storageDirectory.appendingPathComponent("\(key).json")
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                    didMigrate = true
                }
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)

        if didMigrate {
            for key in keys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
