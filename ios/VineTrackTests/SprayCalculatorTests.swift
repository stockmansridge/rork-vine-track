import Testing
import Foundation
@testable import VineTrack

struct SprayCalculatorTests {

    private func squarePaddock(name: String, areaHectares: Double, vineyardId: UUID = UUID()) -> Paddock {
        // Build a square paddock of `areaHectares`. 1 ha = 10,000 m².
        // Side = sqrt(area_m2). Convert metres to degrees at the equator for simplicity.
        let sideMetres = (areaHectares * 10_000).squareRoot()
        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0
        let dLat = sideMetres / mPerDegLat
        let dLon = sideMetres / mPerDegLon
        let lat = 0.0
        let lon = 0.0
        let points = [
            CoordinatePoint(latitude: lat, longitude: lon),
            CoordinatePoint(latitude: lat + dLat, longitude: lon),
            CoordinatePoint(latitude: lat + dLat, longitude: lon + dLon),
            CoordinatePoint(latitude: lat, longitude: lon + dLon),
        ]
        return Paddock(vineyardId: vineyardId, name: name, polygonPoints: points)
    }

    @Test func tankMathWithSinglePaddock() {
        let paddock = squarePaddock(name: "A", areaHectares: 2.0)
        // 500 L/ha × 2 ha = 1000 L, tank capacity 400 L => 3 tanks (2 full + 1 partial 200 L)
        let result = SprayCalculator.calculate(
            selectedPaddocks: [paddock],
            waterRateLitresPerHectare: 500,
            tankCapacity: 400,
            chemicalLines: [],
            chemicals: []
        )
        #expect(abs(result.totalAreaHectares - 2.0) < 0.01)
        #expect(abs(result.totalWaterLitres - 1000) < 1)
        #expect(result.fullTankCount == 2)
        #expect(abs(result.lastTankLitres - 200) < 1)
    }

    @Test func exactTankFit() {
        let paddock = squarePaddock(name: "A", areaHectares: 1.0)
        // 400 L/ha × 1 ha = 400 L, tank 400 L → 1 full tank only.
        let result = SprayCalculator.calculate(
            selectedPaddocks: [paddock],
            waterRateLitresPerHectare: 400,
            tankCapacity: 400,
            chemicalLines: [],
            chemicals: []
        )
        #expect(abs(result.totalWaterLitres - 400) < 1)
        #expect(result.fullTankCount == 0)
        #expect(abs(result.lastTankLitres - 400) < 1)
    }

    @Test func emptyPaddocksReturnZero() {
        let result = SprayCalculator.calculate(
            selectedPaddocks: [],
            waterRateLitresPerHectare: 500,
            tankCapacity: 400,
            chemicalLines: [],
            chemicals: []
        )
        #expect(result.totalAreaHectares == 0)
        #expect(result.totalWaterLitres == 0)
        #expect(result.fullTankCount == 0)
        #expect(result.lastTankLitres == 0)
    }

    @Test func chemicalPerHectareCalculation() {
        let paddock = squarePaddock(name: "A", areaHectares: 2.0)
        let rateId = UUID()
        let chemical = SavedChemical(
            name: "TestChem",
            rates: [ChemicalRate(id: rateId, label: "Label", value: 2.5, basis: .perHectare)]
        )
        let line = ChemicalLine(chemicalId: chemical.id, selectedRateId: rateId, basis: .perHectare)

        let result = SprayCalculator.calculate(
            selectedPaddocks: [paddock],
            waterRateLitresPerHectare: 500,
            tankCapacity: 1000,
            chemicalLines: [line],
            chemicals: [chemical]
        )

        #expect(result.chemicalResults.count == 1)
        // 2.5 × 2 ha = 5
        #expect(abs(result.chemicalResults[0].totalAmountRequired - 5.0) < 0.001)
    }

    @Test func chemicalPer100LitresWithConcentration() {
        let paddock = squarePaddock(name: "A", areaHectares: 1.0)
        let rateId = UUID()
        let chemical = SavedChemical(
            name: "C",
            rates: [ChemicalRate(id: rateId, label: "X", value: 100, basis: .per100Litres)]
        )
        let line = ChemicalLine(chemicalId: chemical.id, selectedRateId: rateId, basis: .per100Litres)

        // 1 ha × 500 L/ha = 500 L water. 500/100 = 5 units × 100 rate × 2× concentration = 1000
        let result = SprayCalculator.calculate(
            selectedPaddocks: [paddock],
            waterRateLitresPerHectare: 500,
            tankCapacity: 500,
            chemicalLines: [line],
            chemicals: [chemical],
            concentrationFactor: 2.0
        )
        #expect(abs(result.chemicalResults[0].totalAmountRequired - 1000) < 1)
    }

    @Test func chemicalCostingAddsUp() {
        let paddock = squarePaddock(name: "A", areaHectares: 1.0)
        let rateId = UUID()
        let purchase = ChemicalPurchase(
            costDollars: 100,
            containerSizeML: 1,
            containerUnit: .litres // 1 L = 1000 mL base → 100/1000 = 0.1 $/mL
        )
        let chemical = SavedChemical(
            name: "C",
            rates: [ChemicalRate(id: rateId, value: 1000, basis: .perHectare)],
            purchase: purchase
        )
        let line = ChemicalLine(chemicalId: chemical.id, selectedRateId: rateId, basis: .perHectare)

        let result = SprayCalculator.calculate(
            selectedPaddocks: [paddock],
            waterRateLitresPerHectare: 500,
            tankCapacity: 1000,
            chemicalLines: [line],
            chemicals: [chemical]
        )
        // total base = 1000 (mL) × 0.1 $/mL = 100
        let summary = result.costingSummary
        #expect(summary != nil)
        #expect(abs((summary?.totalChemicalCost ?? 0) - 100) < 0.01)
    }
}
