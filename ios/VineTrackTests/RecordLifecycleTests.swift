import Testing
import Foundation
@testable import VineTrack

@MainActor
struct RecordLifecycleTests {

    private func makeStore() -> (DataStore, UUID) {
        let store = DataStore()
        let userId = UUID()
        let vineyard = Vineyard(
            name: "Test Vineyard \(UUID().uuidString.prefix(8))",
            users: [VineyardUser(id: userId, name: "Owner", role: .owner)]
        )
        store.addVineyard(vineyard)
        store.selectedVineyardId = vineyard.id
        return (store, vineyard.id)
    }

    // MARK: - Work Tasks

    @Test func workTaskCreateUpdateDelete() {
        let (store, vid) = makeStore()
        let task = WorkTask(vineyardId: vid, taskType: "Pruning", durationHours: 4)
        store.addWorkTask(task)
        #expect(store.workTasks.contains(where: { $0.id == task.id }))

        var updated = task
        updated.taskType = "Cane Tying"
        store.updateWorkTask(updated)
        #expect(store.workTasks.first(where: { $0.id == task.id })?.taskType == "Cane Tying")

        store.deleteWorkTask(task)
        #expect(!store.workTasks.contains(where: { $0.id == task.id }))
    }

    @Test func workTaskArchiveRestore() {
        let (store, vid) = makeStore()
        let task = WorkTask(vineyardId: vid, taskType: "Pruning")
        store.addWorkTask(task)

        store.archiveWorkTask(task)
        let archived = store.workTasks.first { $0.id == task.id }
        #expect(archived?.isArchived == true)
        #expect(archived?.archivedAt != nil)

        store.restoreWorkTask(task)
        let restored = store.workTasks.first { $0.id == task.id }
        #expect(restored?.isArchived == false)
        #expect(restored?.archivedAt == nil)
    }

    @Test func workTaskFinalizeReopen() {
        let (store, vid) = makeStore()
        let task = WorkTask(vineyardId: vid, taskType: "Mowing")
        store.addWorkTask(task)

        store.finalizeWorkTask(task)
        let finalized = store.workTasks.first { $0.id == task.id }
        #expect(finalized?.isFinalized == true)
        #expect(finalized?.finalizedAt != nil)

        store.reopenWorkTask(task)
        let reopened = store.workTasks.first { $0.id == task.id }
        #expect(reopened?.isFinalized == false)
        #expect(reopened?.finalizedAt == nil)
    }

    // MARK: - Maintenance Logs

    @Test func maintenanceLogLifecycle() {
        let (store, vid) = makeStore()
        let log = MaintenanceLog(vineyardId: vid, itemName: "Tractor", hours: 2)
        store.addMaintenanceLog(log)
        #expect(store.maintenanceLogs.contains(where: { $0.id == log.id }))

        store.archiveMaintenanceLog(log)
        #expect(store.maintenanceLogs.first(where: { $0.id == log.id })?.isArchived == true)

        store.restoreMaintenanceLog(log)
        #expect(store.maintenanceLogs.first(where: { $0.id == log.id })?.isArchived == false)

        store.finalizeMaintenanceLog(log)
        #expect(store.maintenanceLogs.first(where: { $0.id == log.id })?.isFinalized == true)

        store.reopenMaintenanceLog(log)
        #expect(store.maintenanceLogs.first(where: { $0.id == log.id })?.isFinalized == false)

        store.deleteMaintenanceLog(log)
        #expect(!store.maintenanceLogs.contains(where: { $0.id == log.id }))
    }

    // MARK: - Spray Records

    @Test func sprayRecordCRUD() {
        let (store, vid) = makeStore()
        let record = SprayRecord(vineyardId: vid, sprayReference: "SPR-001")
        store.addSprayRecord(record)
        #expect(store.sprayRecords.contains(where: { $0.id == record.id }))

        var updated = record
        updated.sprayReference = "SPR-002"
        store.updateSprayRecord(updated)
        #expect(store.sprayRecords.first(where: { $0.id == record.id })?.sprayReference == "SPR-002")

        store.deleteSprayRecord(record)
        #expect(!store.sprayRecords.contains(where: { $0.id == record.id }))
    }

    // MARK: - Pins

    @Test func pinLifecycle() {
        let (store, _) = makeStore()
        let pin = VinePin(
            latitude: -41.0, longitude: 174.0, heading: 0,
            buttonName: "Broken Post", buttonColor: "brown",
            side: .left, mode: .repairs
        )
        store.addPin(pin)
        #expect(store.pins.contains(where: { $0.id == pin.id }))

        store.togglePinCompletion(pin, by: "Tester")
        #expect(store.pins.first(where: { $0.id == pin.id })?.isCompleted == true)

        store.togglePinCompletion(pin)
        #expect(store.pins.first(where: { $0.id == pin.id })?.isCompleted == false)

        store.deletePin(pin)
        #expect(!store.pins.contains(where: { $0.id == pin.id }))
    }

    // MARK: - Trips

    @Test func tripStartUpdateEndDelete() {
        let (store, vid) = makeStore()
        let trip = Trip(vineyardId: vid, paddockName: "A")
        store.startTrip(trip)
        #expect(store.trips.contains(where: { $0.id == trip.id }))
        #expect(store.activeTrip?.id == trip.id)

        store.endTrip(trip)
        let ended = store.trips.first { $0.id == trip.id }
        #expect(ended?.isActive == false)
        #expect(ended?.endTime != nil)
        #expect(store.activeTrip == nil)

        store.deleteTrip(trip)
        #expect(!store.trips.contains(where: { $0.id == trip.id }))
    }

    // MARK: - Permission-blocked deletes

    @Test func operatorCannotDelete() {
        let store = DataStore()
        let userId = UUID()
        let vineyard = Vineyard(
            name: "Blocked",
            users: [VineyardUser(id: userId, name: "Op", role: .operator_)]
        )
        store.addVineyard(vineyard)
        store.selectedVineyardId = vineyard.id

        let auth = AuthService()
        auth.userId = userId.uuidString
        auth.userName = "Op"
        let ac = AccessControl(store: store, authService: auth)
        store.accessControl = ac

        let task = WorkTask(vineyardId: vineyard.id, taskType: "Pruning")
        store.addWorkTask(task)
        store.deleteWorkTask(task)
        // Operator is blocked — task should still exist.
        #expect(store.workTasks.contains(where: { $0.id == task.id }))
    }
}
