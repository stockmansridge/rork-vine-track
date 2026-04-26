import Foundation

extension DataStore {

    /// Returns true if the local store currently holds at least one row for
    /// the given (data type, vineyard) pair. Used by `CloudSyncService` so a
    /// drifted local timestamp can never keep the device empty when the
    /// cloud still has authoritative data.
    func hasLocalData(forDataType dataType: String, vineyardId: UUID) -> Bool {
        switch dataType {
        case "pins":
            return allPins.contains { $0.vineyardId == vineyardId }
        case "paddocks":
            return allPaddocks.contains { $0.vineyardId == vineyardId }
        case "trips":
            return allTrips.contains { $0.vineyardId == vineyardId }
        case "repair_buttons":
            return allRepairButtons.contains { $0.vineyardId == vineyardId }
        case "growth_buttons":
            return allGrowthButtons.contains { $0.vineyardId == vineyardId }
        case "settings":
            return allSettings.contains { $0.vineyardId == vineyardId }
        case "custom_patterns":
            return allCustomPatterns.contains { $0.vineyardId == vineyardId }
        case "spray_records":
            return allSprayRecords.contains { $0.vineyardId == vineyardId }
        case "saved_chemicals":
            return allSavedChemicals.contains { $0.vineyardId == vineyardId }
        case "saved_spray_presets":
            return allSavedSprayPresets.contains { $0.vineyardId == vineyardId }
        case "saved_equipment_options":
            return allSavedEquipmentOptions.contains { $0.vineyardId == vineyardId }
        case "spray_equipment":
            return allSprayEquipment.contains { $0.vineyardId == vineyardId }
        case "tractors":
            return allTractors.contains { $0.vineyardId == vineyardId }
        case "fuel_purchases":
            return allFuelPurchases.contains { $0.vineyardId == vineyardId }
        case "yield_sessions":
            return allYieldSessions.contains { $0.vineyardId == vineyardId }
        case "damage_records":
            return allDamageRecords.contains { $0.vineyardId == vineyardId }
        case "historical_yield_records":
            return allHistoricalYieldRecords.contains { $0.vineyardId == vineyardId }
        case "maintenance_logs":
            return maintenanceLogRepository.loadAll().contains { $0.vineyardId == vineyardId }
        case "work_tasks":
            return workTaskRepository.loadAll().contains { $0.vineyardId == vineyardId }
        case "operator_categories":
            return allOperatorCategories.contains { $0.vineyardId == vineyardId }
        case "button_templates":
            return allButtonTemplates.contains { $0.vineyardId == vineyardId }
        case "grape_varieties":
            let all: [GrapeVariety] = loadData(key: grapeVarietiesKey) ?? []
            return all.contains { $0.vineyardId == vineyardId }
        default:
            return true
        }
    }
}
