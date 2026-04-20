import Testing
import Foundation
@testable import VineTrack

@MainActor
struct SyncMergeTests {

    private func makeStore() -> (DataStore, UUID) {
        let store = DataStore()
        let userId = UUID()
        let vineyard = Vineyard(
            name: "Sync \(UUID().uuidString.prefix(6))",
            users: [VineyardUser(id: userId, name: "Owner", role: .owner)]
        )
        store.addVineyard(vineyard)
        store.selectedVineyardId = vineyard.id
        return (store, vineyard.id)
    }

    @Test func mergePinsAddsMissing() {
        let (store, vid) = makeStore()
        let local = VinePin(
            vineyardId: vid, latitude: 0, longitude: 0, heading: 0,
            buttonName: "A", buttonColor: "red", side: .left, mode: .repairs
        )
        store.addPin(local)

        let remote = VinePin(
            vineyardId: vid, latitude: 1, longitude: 1, heading: 0,
            buttonName: "B", buttonColor: "blue", side: .right, mode: .growth
        )
        store.mergePins([remote], for: vid)

        #expect(store.pins.contains(where: { $0.id == local.id }))
        #expect(store.pins.contains(where: { $0.id == remote.id }))
    }

    @Test func mergePinsIgnoresDuplicates() {
        let (store, vid) = makeStore()
        let pin = VinePin(
            vineyardId: vid, latitude: 0, longitude: 0, heading: 0,
            buttonName: "A", buttonColor: "red", side: .left, mode: .repairs
        )
        store.addPin(pin)
        store.mergePins([pin], for: vid)
        let count = store.pins.filter { $0.id == pin.id }.count
        #expect(count == 1)
    }

    @Test func replacePinsOverwritesLocal() {
        let (store, vid) = makeStore()
        let local = VinePin(
            vineyardId: vid, latitude: 0, longitude: 0, heading: 0,
            buttonName: "Old", buttonColor: "red", side: .left, mode: .repairs
        )
        store.addPin(local)

        let remote1 = VinePin(
            vineyardId: vid, latitude: 1, longitude: 1, heading: 0,
            buttonName: "R1", buttonColor: "blue", side: .left, mode: .repairs
        )
        let remote2 = VinePin(
            vineyardId: vid, latitude: 2, longitude: 2, heading: 0,
            buttonName: "R2", buttonColor: "green", side: .right, mode: .growth
        )
        store.replacePins([remote1, remote2], for: vid)
        #expect(store.pins.count == 2)
        #expect(!store.pins.contains(where: { $0.id == local.id }))
    }

    @Test func mergeTripsAddsMissing() {
        let (store, vid) = makeStore()
        let trip = Trip(vineyardId: vid, paddockName: "A")
        store.startTrip(trip)

        let remote = Trip(vineyardId: vid, paddockName: "B", isActive: false)
        store.mergeTrips([remote], for: vid)

        #expect(store.trips.contains(where: { $0.id == trip.id }))
        #expect(store.trips.contains(where: { $0.id == remote.id }))
    }

    @Test func mergePaddocksAddsMissing() {
        let (store, vid) = makeStore()
        let local = Paddock(vineyardId: vid, name: "Local")
        store.addPaddock(local)

        let remote = Paddock(vineyardId: vid, name: "Remote")
        store.mergePaddocks([remote], for: vid)
        #expect(store.paddocks.contains(where: { $0.id == local.id }))
        #expect(store.paddocks.contains(where: { $0.id == remote.id }))
    }

    @Test func mergeSettingsReplacesByVineyard() {
        let (store, vid) = makeStore()
        let remote = AppSettings(vineyardId: vid, seasonStartMonth: 9, seasonStartDay: 15)
        store.mergeSettings([remote], for: vid)
        #expect(store.settings.seasonStartMonth == 9)
        #expect(store.settings.seasonStartDay == 15)
    }

    @Test func mergeWorkTasksUpdatesExisting() {
        let (store, vid) = makeStore()
        let task = WorkTask(vineyardId: vid, taskType: "Pruning", durationHours: 2)
        store.addWorkTask(task)

        var updated = task
        updated.taskType = "Updated"
        updated.durationHours = 5
        store.mergeWorkTasks([updated], for: vid)
        let found = store.workTasks.first { $0.id == task.id }
        #expect(found?.taskType == "Updated")
        #expect(found?.durationHours == 5)
    }

    @Test func replaceWorkTasksOverwrites() {
        let (store, vid) = makeStore()
        store.addWorkTask(WorkTask(vineyardId: vid, taskType: "Old"))
        let r1 = WorkTask(vineyardId: vid, taskType: "New1")
        let r2 = WorkTask(vineyardId: vid, taskType: "New2")
        store.replaceWorkTasks([r1, r2], for: vid)
        #expect(store.workTasks.count == 2)
        #expect(store.workTasks.contains { $0.taskType == "New1" })
        #expect(store.workTasks.contains { $0.taskType == "New2" })
    }

    @Test func mergeVineyardsOnlyAddsNew() {
        let store = DataStore()
        let existing = Vineyard(name: "Existing")
        store.addVineyard(existing)

        let remote = Vineyard(name: "Remote")
        store.mergeVineyards([existing, remote])
        #expect(store.vineyards.contains { $0.id == existing.id })
        #expect(store.vineyards.contains { $0.id == remote.id })
        #expect(store.vineyards.filter { $0.id == existing.id }.count == 1)
    }
}
