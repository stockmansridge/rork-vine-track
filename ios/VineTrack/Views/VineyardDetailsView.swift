import SwiftUI
import MapKit
import CoreLocation

struct VineyardDetailsView: View {
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @State private var selectedPaddock: Paddock? = nil

    private var vineyard: Vineyard? { store.selectedVineyard }
    private var paddocks: [Paddock] { store.orderedPaddocks }

    private var totalAreaHa: Double {
        paddocks.reduce(0) { $0 + $1.areaHectares }
    }

    private var totalVines: Int {
        paddocks.reduce(0) { $0 + $1.effectiveVineCount }
    }

    private var totalTrellisLength: Double {
        paddocks.reduce(0) { $0 + $1.effectiveTotalRowLength }
    }

    private var totalRows: Int {
        paddocks.reduce(0) { $0 + $1.rows.count }
    }

    private var seasonStartDate: Date {
        let cal = Calendar.current
        let now = Date()
        let month = store.settings.seasonStartMonth
        let day = store.settings.seasonStartDay
        let currentMonth = cal.component(.month, from: now)
        let currentDay = cal.component(.day, from: now)
        let year = cal.component(.year, from: now)
        let startYear: Int
        if currentMonth > month || (currentMonth == month && currentDay >= day) {
            startYear = year
        } else {
            startYear = year - 1
        }
        return cal.date(from: DateComponents(year: startYear, month: month, day: day)) ?? now
    }

    private var seasonTrips: [Trip] {
        store.trips.filter { !$0.isActive && $0.startTime >= seasonStartDate }
    }

    private var seasonSprayRecords: [SprayRecord] {
        store.sprayRecords.filter { !$0.isTemplate && $0.date >= seasonStartDate }
    }

    private var totalTripCosts: Double {
        var total: Double = 0
        for trip in seasonTrips {
            let sprayRecord = store.sprayRecord(for: trip.id)
            let chemCost = (sprayRecord?.tanks ?? []).flatMap { $0.chemicals }.reduce(0.0) { $0 + ($1.costPerUnit * $1.volumePerTank) }

            var fuelCost: Double = 0
            if let record = sprayRecord {
                let tractor = store.tractors.first(where: { $0.displayName == record.tractor || $0.name == record.tractor })
                if let tractor, tractor.fuelUsageLPerHour > 0 {
                    let fuelPrice = store.seasonFuelCostPerLitre
                    if fuelPrice > 0 {
                        fuelCost = fuelPrice * tractor.fuelUsageLPerHour * (trip.activeDuration / 3600.0)
                    }
                }
            }

            var operatorCost: Double = 0
            if !trip.personName.isEmpty,
               let category = store.operatorCategoryForName(trip.personName),
               category.costPerHour > 0 {
                operatorCost = category.costPerHour * (trip.activeDuration / 3600.0)
            }

            total += chemCost + fuelCost + operatorCost
        }
        return total
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                mapSection
                vineyardStatsSection
                blocksSection
                pinsOverviewSection
                seasonSummarySection
                VineyardCostsSection()
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Vineyard Details")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Map

    private var mapSection: some View {
        VineyardBlocksMapView(selectedPaddock: $selectedPaddock)
            .sheet(item: $selectedPaddock) { paddock in
                BlockDetailSheet(paddock: paddock)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    // MARK: - Vineyard Stats

    private var vineyardStatsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Vineyard Summary")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 12)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statCard(label: "Total Area", value: String(format: "%.2f ha", totalAreaHa), icon: "map", color: VineyardTheme.leafGreen)
                statCard(label: "Total Vines", value: formatLargeNumber(totalVines), icon: "leaf", color: VineyardTheme.olive)
                statCard(label: "Trellis Length", value: formatDistance(totalTrellisLength), icon: "ruler", color: VineyardTheme.earthBrown)
                statCard(label: "Total Rows", value: "\(totalRows)", icon: "line.3.horizontal", color: .blue)
            }
        }
    }

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    // MARK: - Blocks

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blocks")
                .font(.headline)

            if paddocks.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No blocks configured")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            } else {
                ForEach(paddocks) { paddock in
                    BlockInfoCard(paddock: paddock, store: store)
                }
            }
        }
    }

    // MARK: - Pins Overview

    private var pinsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pins by Block")
                .font(.headline)

            let blocksWithPins = paddocks.filter { paddock in
                store.pins.contains { $0.paddockId == paddock.id }
            }

            if blocksWithPins.isEmpty && store.pins.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "mappin")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No pins recorded")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            } else {
                ForEach(paddocks) { paddock in
                    let blockPins = store.pins.filter { $0.paddockId == paddock.id }
                    if !blockPins.isEmpty {
                        PinsSummaryCard(paddock: paddock, pins: blockPins)
                    }
                }

                let unassignedPins = store.pins.filter { $0.paddockId == nil }
                if !unassignedPins.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unassigned")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            pinCategoryCount(label: "Repairs", count: unassignedPins.filter { $0.mode == .repairs }.count, color: .orange)
                            pinCategoryCount(label: "Growth", count: unassignedPins.filter { $0.mode == .growth }.count, color: VineyardTheme.leafGreen)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Season Summary

    private var seasonSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Season Summary")
                .font(.headline)

            VStack(spacing: 1) {
                seasonRow(icon: "sprinkler.and.droplets.fill", iconColor: .purple, label: "Sprays This Season", value: "\(seasonSprayRecords.count)")
                seasonRow(icon: "road.lanes", iconColor: .blue, label: "Trips This Season", value: "\(seasonTrips.count)")
                seasonRow(icon: "dollarsign.circle.fill", iconColor: VineyardTheme.leafGreen, label: "Total Trip Costs", value: totalTripCosts > 0 ? String(format: "$%.2f", totalTripCosts) : "–")
            }
        }
    }

    private func seasonRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.1), in: .rect(cornerRadius: 10))

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}

// MARK: - Block Info Card

private struct BlockInfoCard: View {
    let paddock: Paddock
    let store: DataStore

    private var rowNumbers: [Int] {
        paddock.rows.map { $0.number }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GrapeLeafIcon(size: 16)
                    .foregroundStyle(VineyardTheme.olive)
                Text(paddock.name)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(String(format: "%.2f ha", paddock.areaHectares))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VineyardTheme.leafGreen)
            }

            Divider()

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                blockStat(label: "Vines", value: "\(paddock.effectiveVineCount)")
                blockStat(label: "Trellis", value: formatBlockDistance(paddock.effectiveTotalRowLength))
                blockStat(label: "Rows", value: "\(paddock.rows.count)")
            }

            if let first = rowNumbers.first, let last = rowNumbers.last, first != last {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Rows \(first)–\(last)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if paddock.flowPerEmitter != nil || paddock.emitterSpacing != nil {
                Divider()
                irrigationDetails
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var irrigationDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Irrigation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                if let flow = paddock.flowPerEmitter {
                    irrigationStat(label: "Emitter Rate", value: String(format: "%.1f L/hr", flow))
                }
                if let spacing = paddock.emitterSpacing {
                    irrigationStat(label: "Emitter Spacing", value: String(format: "%.1f m", spacing))
                }
                if let totalEmitters = paddock.totalEmitters {
                    irrigationStat(label: "Emitters", value: "\(totalEmitters)")
                }
                if let lVineHr = paddock.litresPerVinePerHour {
                    irrigationStat(label: "L/Vine/Hr", value: String(format: "%.1f", lVineHr))
                }
                if let lph = paddock.litresPerHour {
                    irrigationStat(label: "Block L/hr", value: formatLitresPerHour(lph))
                }
                if let lphha = paddock.litresPerHaPerHour {
                    irrigationStat(label: "L/ha/hr", value: String(format: "%.0f", lphha))
                }
            }
        }
    }

    private func blockStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func irrigationStat(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
    }

    private func formatBlockDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }

    private func formatLitresPerHour(_ lph: Double) -> String {
        if lph >= 1000 {
            return String(format: "%.1fk L/hr", lph / 1000)
        }
        return String(format: "%.0f L/hr", lph)
    }
}

// MARK: - Pins Summary Card

private struct PinsSummaryCard: View {
    let paddock: Paddock
    let pins: [VinePin]

    private var repairPins: [VinePin] { pins.filter { $0.mode == .repairs } }
    private var growthPins: [VinePin] { pins.filter { $0.mode == .growth } }
    private var unresolvedRepairs: Int { repairPins.filter { !$0.isCompleted }.count }
    private var completedRepairs: Int { repairPins.filter { $0.isCompleted }.count }

    private var repairCategories: [(String, Int)] {
        var counts: [String: Int] = [:]
        for pin in repairPins {
            counts[pin.buttonName, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GrapeLeafIcon(size: 14)
                    .foregroundStyle(VineyardTheme.olive)
                Text(paddock.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(pins.count) pins")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                pinCategoryCount(label: "Repairs", count: repairPins.count, color: .orange)
                pinCategoryCount(label: "Growth", count: growthPins.count, color: VineyardTheme.leafGreen)
                if unresolvedRepairs > 0 {
                    pinCategoryCount(label: "Open", count: unresolvedRepairs, color: .red)
                }
                if completedRepairs > 0 {
                    pinCategoryCount(label: "Resolved", count: completedRepairs, color: .green)
                }
            }

            if !repairCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(repairCategories, id: \.0) { category, count in
                            HStack(spacing: 4) {
                                Text(category)
                                    .font(.caption2)
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}

private func pinCategoryCount(label: String, count: Int, color: Color) -> some View {
    HStack(spacing: 4) {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
        Text("\(count)")
            .font(.caption.weight(.semibold).monospacedDigit())
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Block Detail Sheet

private struct BlockDetailSheet: View {
    let paddock: Paddock
    @Environment(DataStore.self) private var store

    private var blockPins: [VinePin] {
        store.pins.filter { $0.paddockId == paddock.id }
    }

    private var blockTrips: [Trip] {
        store.trips.filter { !$0.isActive && $0.paddockIds.contains(paddock.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    LabeledContent("Area", value: String(format: "%.2f ha", paddock.areaHectares))
                    LabeledContent("Vines", value: "\(paddock.effectiveVineCount)")
                    LabeledContent("Trellis Length", value: String(format: "%.0f m", paddock.effectiveTotalRowLength))
                    LabeledContent("Rows", value: "\(paddock.rows.count)")
                    LabeledContent("Row Spacing", value: String(format: "%.1f m", paddock.rowWidth))
                    LabeledContent("Vine Spacing", value: String(format: "%.1f m", paddock.vineSpacing))
                }

                if paddock.flowPerEmitter != nil || paddock.emitterSpacing != nil {
                    Section("Irrigation") {
                        if let flow = paddock.flowPerEmitter {
                            LabeledContent("Emitter Rate", value: String(format: "%.1f L/hr", flow))
                        }
                        if let spacing = paddock.emitterSpacing {
                            LabeledContent("Emitter Spacing", value: String(format: "%.1f m", spacing))
                        }
                        if let totalEmitters = paddock.totalEmitters {
                            LabeledContent("Emitters", value: "\(totalEmitters)")
                        }
                        if let lVineHr = paddock.litresPerVinePerHour {
                            LabeledContent("L/Vine/Hr", value: String(format: "%.1f", lVineHr))
                        }
                        if let lph = paddock.litresPerHour {
                            LabeledContent("Block L/hr", value: String(format: "%.0f", lph))
                        }
                        if let lphha = paddock.litresPerHaPerHour {
                            LabeledContent("L/ha/hr", value: String(format: "%.0f", lphha))
                        }
                    }
                }

                Section("Pins") {
                    LabeledContent("Total Pins", value: "\(blockPins.count)")
                    LabeledContent("Repair Pins", value: "\(blockPins.filter { $0.mode == .repairs }.count)")
                    LabeledContent("Growth Pins", value: "\(blockPins.filter { $0.mode == .growth }.count)")
                    LabeledContent("Unresolved", value: "\(blockPins.filter { !$0.isCompleted && $0.mode == .repairs }.count)")
                }

                Section("Activity") {
                    LabeledContent("Trips", value: "\(blockTrips.count)")
                    let blockSprays = store.sprayRecords.filter { record in
                        blockTrips.contains { $0.id == record.tripId }
                    }
                    LabeledContent("Sprays", value: "\(blockSprays.count)")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(paddock.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
