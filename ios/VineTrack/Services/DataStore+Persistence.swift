import Foundation

extension DataStore {

    func save<T: Encodable>(_ data: T, key: String) {
        do {
            let encoded = try JSONEncoder().encode(data)
            let fileURL = Self.storageDirectory.appendingPathComponent("\(key).json")
            try encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("DataStore: Failed to save \(key): \(error)")
        }
    }

    func loadData<T: Decodable>(key: String) -> T? {
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

    func syncVineyardToCloud(_ vineyard: Vineyard) {
        guard let sync = cloudSync else { return }
        Task { try? await sync.uploadVineyard(vineyard) }
    }

    func syncDataToCloud(dataType: String) {
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
            case "button_templates": return buttonTemplates as [ButtonTemplate]
            case "maintenance_logs": return maintenanceLogs as [MaintenanceLog]
            case "work_tasks": return workTasks as [WorkTask]
            case "yield_sessions": return yieldSessions as [YieldEstimationSession]
            case "damage_records": return damageRecords as [DamageRecord]
            case "historical_yield_records": return historicalYieldRecords as [HistoricalYieldRecord]
            case "grape_varieties": return grapeVarieties as [GrapeVariety]
            case "el_stage_images_manifest": return elStageImageManifest(for: vid)
            default: return [] as [String]
            }
        }()
        Task { await sync.uploadDataForVineyard(vid, dataType: dataType, data: dataToSync) }
    }

    // MARK: - Migration

    func migrateFromUserDefaultsIfNeeded() {
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
