import Testing
import Foundation
@testable import VineTrack

@MainActor
struct YieldCalculationTests {

    private func squarePaddock(areaHectares: Double, vineyardId: UUID) -> Paddock {
        let sideMetres = (areaHectares * 10_000).squareRoot()
        let mPerDeg = 111_320.0
        let d = sideMetres / mPerDeg
        let points = [
            CoordinatePoint(latitude: 0, longitude: 0),
            CoordinatePoint(latitude: d, longitude: 0),
            CoordinatePoint(latitude: d, longitude: d),
            CoordinatePoint(latitude: 0, longitude: d),
        ]
        return Paddock(vineyardId: vineyardId, name: "P", polygonPoints: points, vineCountOverride: 1000)
    }

    @Test func emptySamplesReturnsZeroYield() {
        let vid = UUID()
        let paddock = squarePaddock(areaHectares: 1.0, vineyardId: vid)
        let vm = YieldEstimationViewModel()
        vm.selectedPaddockIds = [paddock.id]
        vm.setBunchWeight(0.15, for: paddock.id)
        let estimates = vm.calculateYieldEstimates(paddocks: [paddock])
        #expect(estimates.count == 1)
        #expect(estimates[0].estimatedYieldKg == 0)
        #expect(estimates[0].samplesRecorded == 0)
    }

    @Test func yieldFromBunchCountsAndWeight() {
        let vid = UUID()
        let paddock = squarePaddock(areaHectares: 1.0, vineyardId: vid)
        let vm = YieldEstimationViewModel()
        vm.selectedPaddockIds = [paddock.id]
        vm.setBunchWeight(0.2, for: paddock.id)

        // Manually inject two recorded samples with 10 bunches/vine average.
        let site1 = SampleSite(
            paddockId: paddock.id, rowNumber: 1, latitude: 0, longitude: 0, siteIndex: 1,
            bunchCountEntry: BunchCountEntry(bunchesPerVine: 8)
        )
        let site2 = SampleSite(
            paddockId: paddock.id, rowNumber: 2, latitude: 0, longitude: 0, siteIndex: 2,
            bunchCountEntry: BunchCountEntry(bunchesPerVine: 12)
        )
        vm.sampleSites = [site1, site2]
        vm.isGenerated = true

        let estimates = vm.calculateYieldEstimates(paddocks: [paddock])
        #expect(estimates.count == 1)
        // 1000 vines × 10 bunches × 0.2 kg × 1.0 damage = 2000 kg
        #expect(abs(estimates[0].estimatedYieldKg - 2000) < 1)
        #expect(abs(estimates[0].estimatedYieldTonnes - 2.0) < 0.01)
        #expect(estimates[0].samplesRecorded == 2)
    }

    @Test func damageFactorReducesYield() {
        let vid = UUID()
        let paddock = squarePaddock(areaHectares: 1.0, vineyardId: vid)
        let vm = YieldEstimationViewModel()
        vm.selectedPaddockIds = [paddock.id]
        vm.setBunchWeight(0.1, for: paddock.id)
        vm.sampleSites = [
            SampleSite(
                paddockId: paddock.id, rowNumber: 1, latitude: 0, longitude: 0, siteIndex: 1,
                bunchCountEntry: BunchCountEntry(bunchesPerVine: 10)
            )
        ]
        vm.isGenerated = true

        let estimates = vm.calculateYieldEstimates(paddocks: [paddock]) { _ in 0.5 }
        // 1000 × 10 × 0.1 × 0.5 = 500
        #expect(abs(estimates[0].estimatedYieldKg - 500) < 1)
        #expect(abs(estimates[0].damageFactor - 0.5) < 0.001)
    }

    @Test func togglePaddockResetsSites() {
        let vm = YieldEstimationViewModel()
        let id = UUID()
        vm.togglePaddock(id)
        #expect(vm.selectedPaddockIds.contains(id))
        vm.togglePaddock(id)
        #expect(!vm.selectedPaddockIds.contains(id))
    }
}
