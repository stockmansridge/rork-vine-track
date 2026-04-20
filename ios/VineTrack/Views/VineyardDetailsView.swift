import SwiftUI
import MapKit
import CoreLocation

struct VineyardDetailsView: View {
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @Environment(DegreeDayService.self) private var degreeDayService
    @Environment(\.accessControl) private var accessControl
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

    private var defaultSeasonStartDate: Date {
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

    private var seasonStartDate: Date {
        let cal = Calendar.current
        let now = Date()
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let seasonStart = defaultSeasonStartDate
        let resetDefault = store.settings.resetMode
        let dates: [Date] = paddocks.compactMap { paddock in
            let mode = paddock.effectiveResetMode(defaultMode: resetDefault)
            return paddock.resetDate(for: mode, seasonStart: seasonStart)
        }.filter { $0 <= now && $0 >= oneYearAgo }
        if let earliest = dates.min() {
            return cal.startOfDay(for: earliest)
        }
        return seasonStart
    }

    private func gddSinceBudburst(for aggregate: VarietyAggregate) -> Double? {
        guard let stationId = store.settings.weatherStationId, !stationId.isEmpty else { return nil }
        let cal = Calendar.current
        let now = Date()
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let seasonStart = defaultSeasonStartDate
        let resetDefault = store.settings.resetMode
        let modeDefault = store.settings.calculationMode
        let blocks = paddocks.filter { paddock in
            paddock.varietyAllocations.contains(where: { $0.varietyId == aggregate.id })
        }
        var totals: [Double] = []
        for block in blocks {
            let resetMode = block.effectiveResetMode(defaultMode: resetDefault)
            guard let resetDate = block.resetDate(for: resetMode, seasonStart: seasonStart),
                  resetDate <= now, resetDate >= oneYearAgo else { continue }
            let calcMode = block.effectiveCalculationMode(defaultMode: modeDefault)
            let result = degreeDayService.computeGDD(
                stationId: stationId,
                from: cal.startOfDay(for: resetDate),
                to: cal.startOfDay(for: now),
                latitude: effectiveLatitude,
                useBEDD: calcMode.useBEDD
            )
            totals.append(result.gdd)
        }
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / Double(totals.count)
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
                degreeDaysSection
                varietyRipenessSection
                blocksSection
                pinsOverviewSection
                seasonSummarySection
                if accessControl?.canViewFinancials ?? false {
                    VineyardCostsSection()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Vineyard Details")
        .navigationBarTitleDisplayMode(.large)
        .task(id: store.settings.weatherStationId) {
            await refreshDegreeDays()
        }
    }

    private var effectiveLatitude: Double? {
        store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
    }

    private func refreshDegreeDays() async {
        guard let stationId = store.settings.weatherStationId, !stationId.isEmpty else { return }
        await degreeDayService.fetchSeasonGDD(
            stationId: stationId,
            seasonStart: seasonStartDate,
            latitude: effectiveLatitude,
            useBEDD: store.settings.calculationMode.useBEDD
        )
    }

    private func formatRangeDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    fileprivate struct VarietyAggregate: Identifiable {
        let id: UUID
        let name: String
        let optimalGDD: Double
        let hectares: Double
        let totalVineyardHa: Double
        var sharePercent: Double { totalVineyardHa > 0 ? (hectares / totalVineyardHa) * 100 : 0 }
    }

    private var varietyAggregates: [VarietyAggregate] {
        var totals: [UUID: Double] = [:]
        var totalHa: Double = 0
        for paddock in paddocks {
            let blockArea = paddock.areaHectares
            totalHa += blockArea
            for alloc in paddock.varietyAllocations {
                totals[alloc.varietyId, default: 0] += blockArea * (alloc.percent / 100.0)
            }
        }
        return totals.compactMap { id, ha -> VarietyAggregate? in
            guard let variety = store.grapeVariety(for: id) else { return nil }
            return VarietyAggregate(
                id: id,
                name: variety.name,
                optimalGDD: variety.optimalGDD,
                hectares: ha,
                totalVineyardHa: totalHa
            )
        }
        .sorted { $0.hectares > $1.hectares }
    }

    @State private var showGDDInfo: Bool = false
    @State private var showDataHealth: Bool = false

    private var dataHealthColor: Color {
        let expected = max(degreeDayService.expectedDays, 1)
        let reported = max(0, degreeDayService.daysCovered - degreeDayService.interpolatedDays)
        let pct = Double(reported) / Double(expected)
        return pct >= 0.98 ? .green : (pct >= 0.90 ? .orange : .red)
    }

    private var dataHealthButton: some View {
        Button {
            showDataHealth = true
        } label: {
            Image(systemName: "heart.text.square")
                .font(.caption.weight(.semibold))
                .foregroundStyle(degreeDayService.seasonGDD != nil ? dataHealthColor : Color.secondary)
        }
        .popover(isPresented: $showDataHealth, arrowEdge: .top) {
            dataHealthPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var dataHealthPopover: some View {
        let expected = max(degreeDayService.expectedDays, 1)
        let reported = max(0, degreeDayService.daysCovered - degreeDayService.interpolatedDays)
        let pct = Double(reported) / Double(expected)
        let color = dataHealthColor
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(color)
                Text("Data Health")
                    .font(.headline)
            }
            if degreeDayService.seasonGDD != nil {
                HStack {
                    Text("\(reported) / \(degreeDayService.expectedDays) days")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text("\(Int((pct * 100).rounded()))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(color)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(pct, 0), 1)))
                    }
                }
                .frame(height: 6)
                if degreeDayService.interpolatedDays > 0 {
                    Text("\(degreeDayService.interpolatedDays) day\(degreeDayService.interpolatedDays == 1 ? "" : "s") estimated from neighbouring entries")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = degreeDayService.errorMessage {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private var gddInfoButton: some View {
        Button {
            showGDDInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .popover(isPresented: $showGDDInfo, arrowEdge: .top) {
            gddInfoPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var gddInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.settings.calculationMode == .bedd ? "BEDD Formula" : "GDD Formula")
                .font(.headline)
            if store.settings.calculationMode == .bedd {
                Text("BEDD = max(0, ((min(Tmax,19) + min(Tmin,19))/2) − 10) + diurnal bonus")
                    .font(.caption)
                Text("• Daily temps capped at 19°C")
                Text("• +0.25×(range−13) when (Tmax−Tmin) > 13°C")
                Text("• Day-length factor from latitude")
            } else {
                Text("GDD = max(0, ((Tmax + Tmin) / 2) − 10°C)")
                    .font(.caption)
            }
            Divider()
            Text("Season Window").font(.subheadline.weight(.semibold))
            Text("Start: \(seasonStartDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
            Text("End: yesterday (data lags ~1 day)")
                .font(.caption)
            if let lat = effectiveLatitude {
                Text("Latitude: \(String(format: "%.3f°", lat))")
                    .font(.caption)
            }
            Divider()
            Text("Reset Point: \(store.settings.resetMode.displayName)").font(.subheadline.weight(.semibold))
            Text("Variety ripeness uses each block’s own reset date (budburst, flowering, etc).").font(.caption2).foregroundStyle(.secondary)
            Text("Change calculation, reset point, and coordinates in Settings → Vineyard Setup.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .font(.caption2)
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private var dataHealthRow: some View {
        let expected = max(degreeDayService.expectedDays, 1)
        let reported = max(0, degreeDayService.daysCovered - degreeDayService.interpolatedDays)
        let pct = Double(reported) / Double(expected)
        let color: Color = pct >= 0.98 ? .green : (pct >= 0.90 ? .orange : .red)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text("Data health")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(reported) / \(degreeDayService.expectedDays) days · \(Int((pct * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(pct, 0), 1)))
                }
            }
            .frame(height: 6)
            if degreeDayService.interpolatedDays > 0 {
                Text("\(degreeDayService.interpolatedDays) day\(degreeDayService.interpolatedDays == 1 ? "" : "s") estimated from neighbouring entries")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 4)
    }

    private var degreeDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.settings.calculationMode == .bedd ? "Biologically Effective Degree Days" : "Growing Degree Days")
                    .font(.headline)
                Spacer()
                dataHealthButton
                gddInfoButton
                Button {
                    Task { await refreshDegreeDays() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .disabled(degreeDayService.isLoading)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "thermometer.sun.fill")
                        .foregroundStyle(.orange)
                    if let gdd = degreeDayService.seasonGDD {
                        Text("\(Int(gdd))")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        Text("°C\u{00B7}days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if degreeDayService.isLoading {
                        ProgressView()
                        Text("Loading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if degreeDayService.seasonGDD != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Season to date (\(degreeDayService.daysCovered) days, base 10°C\(store.settings.calculationMode == .bedd ? ", capped 19°C" : "")) • from \(store.settings.resetMode.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let lat = effectiveLatitude {
                            Text("Latitude \(String(format: "%.3f°", lat))\(store.settings.vineyardLatitude == nil ? " (auto from blocks)" : "")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let first = degreeDayService.firstDateCovered, let last = degreeDayService.lastDateCovered {
                            Text("Data: \(formatRangeDate(first)) – \(formatRangeDate(last))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let updated = degreeDayService.lastUpdated {
                            Text("Last updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else if (store.settings.weatherStationId ?? "").isEmpty {
                    Text("Set a weather station in Vineyard Setup to track degree days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    private var varietyRipenessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Variety Ripeness")
                .font(.headline)

            if varietyAggregates.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "leaf")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No varieties assigned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Edit a block to assign grape varieties.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            } else {
                VStack(spacing: 10) {
                    ForEach(varietyAggregates) { agg in
                        NavigationLink {
                            VarietyGDDDetailView(varietyId: agg.id)
                        } label: {
                            VarietyRipenessRow(
                                aggregate: agg,
                                seasonGDD: gddSinceBudburst(for: agg) ?? degreeDayService.seasonGDD,
                                usesBlockBudburst: gddSinceBudburst(for: agg) != nil,
                                showsDisclosure: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
                if accessControl?.canViewFinancials ?? false {
                    seasonRow(icon: "dollarsign.circle.fill", iconColor: VineyardTheme.leafGreen, label: "Total Trip Costs", value: totalTripCosts > 0 ? String(format: "$%.2f", totalTripCosts) : "–")
                }
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
                    irrigationStat(label: "Emitters", value: formatCountK(Double(totalEmitters)))
                }
                if let lVineHr = paddock.litresPerVinePerHour {
                    irrigationStat(label: "L/Vine/Hr", value: formatK(lVineHr, suffix: ""))
                }
                if let lph = paddock.litresPerHour {
                    irrigationStat(label: "Block L/hr", value: formatK(lph, suffix: " L/hr"))
                }
                if let lphha = paddock.litresPerHaPerHour {
                    irrigationStat(label: "L/ha/hr", value: formatK(lphha, suffix: ""))
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
        formatK(lph, suffix: " L/hr")
    }

    private func formatK(_ value: Double, suffix: String) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.1fk%@", value / 1000, suffix)
        }
        return String(format: "%.0f%@", value, suffix)
    }

    private func formatCountK(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
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

// MARK: - Variety Ripeness Row

private struct VarietyRipenessRow: View {
    let aggregate: VineyardDetailsView.VarietyAggregate
    let seasonGDD: Double?
    var usesBlockBudburst: Bool = false
    var showsDisclosure: Bool = false

    private var progress: Double {
        guard let gdd = seasonGDD, aggregate.optimalGDD > 0 else { return 0 }
        return min(1.0, max(0, gdd / aggregate.optimalGDD))
    }

    private var progressPercent: Int {
        Int(progress * 100)
    }

    private var progressColor: Color {
        switch progress {
        case 0.98...: return VineyardTheme.leafGreen
        case 0.9..<0.98: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(aggregate.name)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(String(format: "%.1f ha • %.0f%%", aggregate.hectares, aggregate.sharePercent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(progressColor.gradient)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 8)

            HStack {
                if seasonGDD != nil {
                    Text("\(progressPercent)% of optimal\(usesBlockBudburst ? " • from budburst" : "")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(progressColor)
                } else {
                    Text("Awaiting GDD data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Target \(Int(aggregate.optimalGDD)) GDD")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}
