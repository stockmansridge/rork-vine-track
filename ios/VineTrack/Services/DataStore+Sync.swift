import Foundation

extension DataStore {

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

    func mergeOperatorCategories(_ remote: [OperatorCategory], for vineyardId: UUID) {
        var all: [OperatorCategory] = loadData(key: operatorCategoriesKey) ?? []
        for item in remote {
            if let index = all.firstIndex(where: { $0.id == item.id }) {
                all[index] = item
            } else {
                all.append(item)
            }
        }
        save(all, key: operatorCategoriesKey)
        if selectedVineyardId == vineyardId {
            operatorCategories = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceOperatorCategories(_ remote: [OperatorCategory], for vineyardId: UUID) {
        var all: [OperatorCategory] = loadData(key: operatorCategoriesKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: operatorCategoriesKey)
        if selectedVineyardId == vineyardId {
            operatorCategories = remote
        }
    }

    func mergeButtonTemplates(_ remote: [ButtonTemplate], for vineyardId: UUID) {
        var all: [ButtonTemplate] = loadData(key: buttonTemplatesKey) ?? []
        for item in remote {
            if let index = all.firstIndex(where: { $0.id == item.id }) {
                all[index] = item
            } else {
                all.append(item)
            }
        }
        save(all, key: buttonTemplatesKey)
        if selectedVineyardId == vineyardId {
            buttonTemplates = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceButtonTemplates(_ remote: [ButtonTemplate], for vineyardId: UUID) {
        var all: [ButtonTemplate] = loadData(key: buttonTemplatesKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: buttonTemplatesKey)
        if selectedVineyardId == vineyardId {
            buttonTemplates = remote
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

    func saveAllPins() {
        var allPins: [VinePin] = loadData(key: pinsKey) ?? []
        if let vid = selectedVineyardId {
            allPins.removeAll { $0.vineyardId == vid }
        }
        allPins.append(contentsOf: pins)
        save(allPins, key: pinsKey)
        syncDataToCloud(dataType: "pins")
    }

    func saveAllPaddocks() {
        var allPaddocks: [Paddock] = loadData(key: paddocksKey) ?? []
        if let vid = selectedVineyardId {
            allPaddocks.removeAll { $0.vineyardId == vid }
        }
        allPaddocks.append(contentsOf: paddocks)
        save(allPaddocks, key: paddocksKey)
        syncDataToCloud(dataType: "paddocks")
    }

    func saveAllTrips() {
        var allTrips: [Trip] = loadData(key: tripsKey) ?? []
        if let vid = selectedVineyardId {
            allTrips.removeAll { $0.vineyardId == vid }
        }
        allTrips.append(contentsOf: trips)
        save(allTrips, key: tripsKey)
        syncDataToCloud(dataType: "trips")
    }

    func saveAllRepairButtons() {
        var allButtons: [ButtonConfig] = loadData(key: repairButtonsKey) ?? []
        if let vid = selectedVineyardId {
            allButtons.removeAll { $0.vineyardId == vid }
        }
        allButtons.append(contentsOf: repairButtons)
        save(allButtons, key: repairButtonsKey)
        syncDataToCloud(dataType: "repair_buttons")
    }

    func saveAllGrowthButtons() {
        var allButtons: [ButtonConfig] = loadData(key: growthButtonsKey) ?? []
        if let vid = selectedVineyardId {
            allButtons.removeAll { $0.vineyardId == vid }
        }
        allButtons.append(contentsOf: growthButtons)
        save(allButtons, key: growthButtonsKey)
        syncDataToCloud(dataType: "growth_buttons")
    }

    func saveAllSprayRecords() {
        var allRecords: [SprayRecord] = loadData(key: sprayRecordsKey) ?? []
        if let vid = selectedVineyardId {
            allRecords.removeAll { $0.vineyardId == vid }
        }
        allRecords.append(contentsOf: sprayRecords)
        save(allRecords, key: sprayRecordsKey)
        syncDataToCloud(dataType: "spray_records")
    }

    func saveAllSavedChemicals() {
        var all: [SavedChemical] = loadData(key: savedChemicalsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: savedChemicals)
        save(all, key: savedChemicalsKey)
        syncDataToCloud(dataType: "saved_chemicals")
    }

    func saveAllSavedSprayPresets() {
        var all: [SavedSprayPreset] = loadData(key: savedSprayPresetsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: savedSprayPresets)
        save(all, key: savedSprayPresetsKey)
        syncDataToCloud(dataType: "saved_spray_presets")
    }

    func saveAllSavedEquipmentOptions() {
        var all: [SavedEquipmentOption] = loadData(key: savedEquipmentOptionsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: savedEquipmentOptions)
        save(all, key: savedEquipmentOptionsKey)
        syncDataToCloud(dataType: "saved_equipment_options")
    }

    func saveAllSprayEquipment() {
        var all: [SprayEquipmentItem] = loadData(key: sprayEquipmentKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: sprayEquipment)
        save(all, key: sprayEquipmentKey)
        syncDataToCloud(dataType: "spray_equipment")
    }

    func saveAllTractors() {
        var all: [Tractor] = loadData(key: tractorsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: tractors)
        save(all, key: tractorsKey)
        syncDataToCloud(dataType: "tractors")
    }

    func saveAllFuelPurchases() {
        var all: [FuelPurchase] = loadData(key: fuelPurchasesKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: fuelPurchases)
        save(all, key: fuelPurchasesKey)
        syncDataToCloud(dataType: "fuel_purchases")
    }

    func saveAllOperatorCategories() {
        var all: [OperatorCategory] = loadData(key: operatorCategoriesKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: operatorCategories)
        save(all, key: operatorCategoriesKey)
        syncDataToCloud(dataType: "operator_categories")
    }

    func saveAllButtonTemplates() {
        var all: [ButtonTemplate] = loadData(key: buttonTemplatesKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: buttonTemplates)
        save(all, key: buttonTemplatesKey)
        syncDataToCloud(dataType: "button_templates")
    }

    func saveAllDamageRecords() {
        var all: [DamageRecord] = loadData(key: damageRecordsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: damageRecords)
        save(all, key: damageRecordsKey)
        syncDataToCloud(dataType: "damage_records")
    }

    func saveAllMaintenanceLogs() {
        guard let vid = selectedVineyardId else { return }
        maintenanceLogRepository.saveSlice(maintenanceLogs, for: vid)
        syncDataToCloud(dataType: "maintenance_logs")
    }

    func saveAllHistoricalYieldRecords() {
        var all: [HistoricalYieldRecord] = loadData(key: historicalYieldRecordsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: historicalYieldRecords)
        save(all, key: historicalYieldRecordsKey)
        syncDataToCloud(dataType: "historical_yield_records")
    }

    func saveAllYieldSessions() {
        var all: [YieldEstimationSession] = loadData(key: yieldSessionsKey) ?? []
        if let vid = selectedVineyardId {
            all.removeAll { $0.vineyardId == vid }
        }
        all.append(contentsOf: yieldSessions)
        save(all, key: yieldSessionsKey)
        syncDataToCloud(dataType: "yield_sessions")
    }

    // MARK: - Cloud Merge: Yield / Damage / Maintenance

    func replaceYieldSessions(_ remote: [YieldEstimationSession], for vineyardId: UUID) {
        var all: [YieldEstimationSession] = loadData(key: yieldSessionsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: yieldSessionsKey)
        if selectedVineyardId == vineyardId {
            yieldSessions = remote
        }
    }

    func mergeYieldSessions(_ remote: [YieldEstimationSession], for vineyardId: UUID) {
        var all: [YieldEstimationSession] = loadData(key: yieldSessionsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: yieldSessionsKey)
        if selectedVineyardId == vineyardId {
            yieldSessions = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceDamageRecords(_ remote: [DamageRecord], for vineyardId: UUID) {
        var all: [DamageRecord] = loadData(key: damageRecordsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: damageRecordsKey)
        if selectedVineyardId == vineyardId {
            damageRecords = remote
        }
    }

    func mergeDamageRecords(_ remote: [DamageRecord], for vineyardId: UUID) {
        var all: [DamageRecord] = loadData(key: damageRecordsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: damageRecordsKey)
        if selectedVineyardId == vineyardId {
            damageRecords = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceHistoricalYieldRecords(_ remote: [HistoricalYieldRecord], for vineyardId: UUID) {
        var all: [HistoricalYieldRecord] = loadData(key: historicalYieldRecordsKey) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: remote)
        save(all, key: historicalYieldRecordsKey)
        if selectedVineyardId == vineyardId {
            historicalYieldRecords = remote
        }
    }

    func mergeHistoricalYieldRecords(_ remote: [HistoricalYieldRecord], for vineyardId: UUID) {
        var all: [HistoricalYieldRecord] = loadData(key: historicalYieldRecordsKey) ?? []
        for item in remote {
            if !all.contains(where: { $0.id == item.id }) {
                all.append(item)
            }
        }
        save(all, key: historicalYieldRecordsKey)
        if selectedVineyardId == vineyardId {
            historicalYieldRecords = all.filter { $0.vineyardId == vineyardId }
        }
    }

    func replaceMaintenanceLogs(_ remote: [MaintenanceLog], for vineyardId: UUID) {
        maintenanceLogRepository.replace(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            maintenanceLogs = remote
        }
    }

    func mergeMaintenanceLogs(_ remote: [MaintenanceLog], for vineyardId: UUID) {
        let merged = maintenanceLogRepository.merge(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            maintenanceLogs = merged
        }
    }

    func saveAllCustomPatterns() {
        var allPatterns: [SavedCustomPattern] = loadData(key: customPatternsKey) ?? []
        if let vid = selectedVineyardId {
            allPatterns.removeAll { $0.vineyardId == vid }
        }
        allPatterns.append(contentsOf: savedCustomPatterns)
        save(allPatterns, key: customPatternsKey)
        syncDataToCloud(dataType: "custom_patterns")
    }

}
