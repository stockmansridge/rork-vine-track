import Foundation

extension DataStore {

    // MARK: - Cloud Merge Helpers

    func mergeVineyards(_ remote: [Vineyard]) {
        vineyards = vineyardRepository.merge(remote)
        // Clear any stale selection that points to a vineyard the current
        // user no longer has access to (e.g. after switching accounts on a
        // shared device). When the user has multiple vineyards we leave the
        // selection nil so the picker is shown; with exactly one vineyard
        // we auto-select it for convenience.
        if let sel = selectedVineyardId, !vineyards.contains(where: { $0.id == sel }) {
            selectedVineyardId = nil
        }
        if selectedVineyardId == nil, vineyards.count == 1, let only = vineyards.first {
            selectedVineyardId = only.id
        }
    }

    func mergePins(_ remote: [VinePin], for vineyardId: UUID) {
        let merged = pinRepository.merge(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            pins = merged
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
        let merged = tripRepository.merge(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            trips = merged
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
        _ = settingsRepository.merge(remote, for: vineyardId)
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
        pinRepository.replace(remote, for: vineyardId)
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
        tripRepository.replace(remote, for: vineyardId)
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
        let merged = sprayRepository.mergeChemicals(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            savedChemicals = merged
        }
    }

    func replaceSavedChemicals(_ remote: [SavedChemical], for vineyardId: UUID) {
        sprayRepository.replaceChemicals(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            savedChemicals = remote
        }
    }

    func mergeSavedSprayPresets(_ remote: [SavedSprayPreset], for vineyardId: UUID) {
        let merged = sprayRepository.mergePresets(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            savedSprayPresets = merged
        }
    }

    func replaceSavedSprayPresets(_ remote: [SavedSprayPreset], for vineyardId: UUID) {
        sprayRepository.replacePresets(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            savedSprayPresets = remote
        }
    }

    func mergeSavedEquipmentOptions(_ remote: [SavedEquipmentOption], for vineyardId: UUID) {
        let merged = sprayRepository.mergeEquipmentOptions(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            savedEquipmentOptions = merged
        }
    }

    func replaceSavedEquipmentOptions(_ remote: [SavedEquipmentOption], for vineyardId: UUID) {
        sprayRepository.replaceEquipmentOptions(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            savedEquipmentOptions = remote
        }
    }

    func mergeSprayEquipment(_ remote: [SprayEquipmentItem], for vineyardId: UUID) {
        let merged = sprayRepository.mergeEquipment(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            sprayEquipment = merged
        }
    }

    func replaceSprayEquipment(_ remote: [SprayEquipmentItem], for vineyardId: UUID) {
        sprayRepository.replaceEquipment(remote, for: vineyardId)
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
        sprayRepository.replaceRecords(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            sprayRecords = remote
        }
    }

    func mergeSprayRecords(_ remote: [SprayRecord], for vineyardId: UUID) {
        let merged = sprayRepository.mergeRecords(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            sprayRecords = merged
        }
    }

    // MARK: - Private Save Helpers

    func saveAllPins() {
        guard let vid = selectedVineyardId else { return }
        pinRepository.saveSlice(pins, for: vid)
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
        guard let vid = selectedVineyardId else { return }
        tripRepository.saveSlice(trips, for: vid)
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
        guard let vid = selectedVineyardId else { return }
        sprayRepository.saveRecordsSlice(sprayRecords, for: vid)
        syncDataToCloud(dataType: "spray_records")
    }

    func saveAllSavedChemicals() {
        guard let vid = selectedVineyardId else { return }
        sprayRepository.saveChemicalsSlice(savedChemicals, for: vid)
        syncDataToCloud(dataType: "saved_chemicals")
    }

    func saveAllSavedSprayPresets() {
        guard let vid = selectedVineyardId else { return }
        sprayRepository.savePresetsSlice(savedSprayPresets, for: vid)
        syncDataToCloud(dataType: "saved_spray_presets")
    }

    func saveAllSavedEquipmentOptions() {
        guard let vid = selectedVineyardId else { return }
        sprayRepository.saveEquipmentOptionsSlice(savedEquipmentOptions, for: vid)
        syncDataToCloud(dataType: "saved_equipment_options")
    }

    func saveAllSprayEquipment() {
        guard let vid = selectedVineyardId else { return }
        sprayRepository.saveEquipmentSlice(sprayEquipment, for: vid)
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
        guard let vid = selectedVineyardId else { return }
        yieldRepository.saveDamageSlice(damageRecords, for: vid)
        syncDataToCloud(dataType: "damage_records")
    }

    func saveAllMaintenanceLogs() {
        guard let vid = selectedVineyardId else { return }
        maintenanceLogRepository.saveSlice(maintenanceLogs, for: vid)
        syncDataToCloud(dataType: "maintenance_logs")
    }

    func saveAllHistoricalYieldRecords() {
        guard let vid = selectedVineyardId else { return }
        yieldRepository.saveHistoricalSlice(historicalYieldRecords, for: vid)
        syncDataToCloud(dataType: "historical_yield_records")
    }

    func saveAllYieldSessions() {
        guard let vid = selectedVineyardId else { return }
        yieldRepository.saveSessionsSlice(yieldSessions, for: vid)
        syncDataToCloud(dataType: "yield_sessions")
    }

    // MARK: - Cloud Merge: Yield / Damage / Maintenance

    func replaceYieldSessions(_ remote: [YieldEstimationSession], for vineyardId: UUID) {
        yieldRepository.replaceSessions(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            yieldSessions = remote
        }
    }

    func mergeYieldSessions(_ remote: [YieldEstimationSession], for vineyardId: UUID) {
        let merged = yieldRepository.mergeSessions(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            yieldSessions = merged
        }
    }

    func replaceDamageRecords(_ remote: [DamageRecord], for vineyardId: UUID) {
        yieldRepository.replaceDamage(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            damageRecords = remote
        }
    }

    func mergeDamageRecords(_ remote: [DamageRecord], for vineyardId: UUID) {
        let merged = yieldRepository.mergeDamage(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            damageRecords = merged
        }
    }

    func replaceHistoricalYieldRecords(_ remote: [HistoricalYieldRecord], for vineyardId: UUID) {
        yieldRepository.replaceHistorical(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            historicalYieldRecords = remote
        }
    }

    func mergeHistoricalYieldRecords(_ remote: [HistoricalYieldRecord], for vineyardId: UUID) {
        let merged = yieldRepository.mergeHistorical(remote, for: vineyardId)
        if selectedVineyardId == vineyardId {
            historicalYieldRecords = merged
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
