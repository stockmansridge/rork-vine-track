import Testing
import Foundation
@testable import VineTrack

struct IrrigationCalculatorTests {

    @Test func returnsNilWhenNoForecast() {
        let result = IrrigationCalculator.calculate(forecastDays: [], settings: .defaults)
        #expect(result == nil)
    }

    @Test func returnsNilWhenApplicationRateZero() {
        let days = [ForecastDay(date: Date(), forecastEToMm: 5, forecastRainMm: 0)]
        // default irrigationApplicationRateMmPerHour is 0 — should return nil.
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: .defaults)
        #expect(result == nil)
    }

    @Test func basicDeficitNoRain() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 4.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 100
        settings.replacementPercent = 100
        settings.soilMoistureBufferMm = 0

        let days = (0..<3).map { i in
            ForecastDay(date: Date().addingTimeInterval(Double(i) * 86_400), forecastEToMm: 4, forecastRainMm: 0)
        }
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        #expect(result != nil)
        // 3 days × 4 mm × 1.0 = 12 mm deficit
        #expect(abs((result?.netDeficitMm ?? 0) - 12) < 0.01)
        #expect(abs((result?.grossIrrigationMm ?? 0) - 12) < 0.01)
        // 12 mm / 4 mm/h = 3h
        #expect(abs((result?.recommendedIrrigationHours ?? 0) - 3.0) < 0.01)
        #expect(result?.recommendedIrrigationMinutes == 180)
    }

    @Test func rainBelow2mmIgnored() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 4.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 100
        settings.rainfallEffectivenessPercent = 100

        let days = [ForecastDay(date: Date(), forecastEToMm: 5, forecastRainMm: 1.5)]
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        // Rain under 2mm should be ignored → deficit 5
        #expect(abs((result?.netDeficitMm ?? 0) - 5) < 0.01)
    }

    @Test func efficiencyIncreasesGrossIrrigation() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 5.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 50
        settings.replacementPercent = 100
        let days = [ForecastDay(date: Date(), forecastEToMm: 10, forecastRainMm: 0)]
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        // net 10 / 0.5 eff = 20 gross
        #expect(abs((result?.grossIrrigationMm ?? 0) - 20) < 0.01)
    }

    @Test func replacementPercentScalesOutput() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 5.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 100
        settings.replacementPercent = 50

        let days = [ForecastDay(date: Date(), forecastEToMm: 10, forecastRainMm: 0)]
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        // deficit 10 × 50% replacement = 5 mm gross
        #expect(abs((result?.grossIrrigationMm ?? 0) - 5) < 0.01)
        #expect(result?.recommendedIrrigationMinutes == 60)
    }

    @Test func rainfallEffectivenessAppliesWhenAbove2mm() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 4.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 100
        settings.rainfallEffectivenessPercent = 50
        settings.replacementPercent = 100

        let days = [ForecastDay(date: Date(), forecastEToMm: 10, forecastRainMm: 10)]
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        // crop use 10, effective rain 10*0.5 = 5, deficit 5
        #expect(abs((result?.netDeficitMm ?? 0) - 5) < 0.01)
    }

    @Test func bufferLargerThanDeficitClampsToZero() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 5.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 100
        settings.replacementPercent = 100
        settings.soilMoistureBufferMm = 100

        let days = [ForecastDay(date: Date(), forecastEToMm: 10, forecastRainMm: 0)]
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        #expect((result?.netDeficitMm ?? -1) == 0)
        #expect(result?.recommendedIrrigationMinutes == 0)
    }

    @Test func minutesRoundToNearest() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 3.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 100
        settings.replacementPercent = 100
        // 5 mm / 3 mm/h = 1.6666 h = 100 minutes
        let days = [ForecastDay(date: Date(), forecastEToMm: 5, forecastRainMm: 0)]
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        #expect(result?.recommendedIrrigationMinutes == 100)
    }

    @Test func soilBufferReducesDeficit() {
        var settings = IrrigationSettings.defaults
        settings.irrigationApplicationRateMmPerHour = 5.0
        settings.cropCoefficientKc = 1.0
        settings.irrigationEfficiencyPercent = 100
        settings.replacementPercent = 100
        settings.soilMoistureBufferMm = 5

        let days = [ForecastDay(date: Date(), forecastEToMm: 10, forecastRainMm: 0)]
        let result = IrrigationCalculator.calculate(forecastDays: days, settings: settings)
        #expect(abs((result?.netDeficitMm ?? 0) - 5) < 0.01)
    }
}
