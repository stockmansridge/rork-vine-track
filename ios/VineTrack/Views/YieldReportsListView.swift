import SwiftUI

struct YieldReportsListView: View {
    @Environment(DataStore.self) private var store
    @State private var showArchiveSheet: Bool = false
    @State private var showHistoricalDetail: HistoricalYieldRecord?
    @State private var historicalSortBy: HistoricalSort = .newest
    @State private var historicalFilterPaddock: UUID?

    private var paddocks: [Paddock] {
        store.orderedPaddocks.filter { $0.polygonPoints.count >= 3 }
    }

    private var sessions: [YieldEstimationSession] {
        store.yieldSessions.sorted { $0.createdAt > $1.createdAt }
    }

    private var blockSummaries: [BlockSummary] {
        var summaries: [BlockSummary] = []

        for paddock in paddocks {
            guard let session = store.yieldSessions.first(where: {
                $0.selectedPaddockIds.contains(paddock.id)
            }) else { continue }

            let sites = session.sampleSites.filter { $0.paddockId == paddock.id }
            let recorded = sites.filter { $0.isRecorded }

            guard !recorded.isEmpty else {
                summaries.append(BlockSummary(
                    paddockId: paddock.id,
                    paddockName: paddock.name,
                    areaHa: paddock.areaHectares,
                    yieldTonnes: 0,
                    yieldPerHa: 0,
                    samplesRecorded: 0,
                    samplesTotal: sites.count,
                    lastUpdated: session.createdAt
                ))
                continue
            }

            let avgBunches = recorded.reduce(0.0) { $0 + ($1.bunchCountEntry?.bunchesPerVine ?? 0) } / Double(recorded.count)
            let avgBunchesRounded = (avgBunches * 100).rounded() / 100
            let totalVines = paddock.effectiveVineCount
            let totalBunches = Double(totalVines) * avgBunchesRounded
            let damageFactor = store.damageFactor(for: paddock.id)
            let yieldKg = totalBunches * session.bunchWeightKg(for: paddock.id) * damageFactor
            let yieldTonnes = yieldKg / 1000.0

            let latestDate = recorded
                .compactMap { $0.bunchCountEntry?.recordedAt }
                .max() ?? session.createdAt

            summaries.append(BlockSummary(
                paddockId: paddock.id,
                paddockName: paddock.name,
                areaHa: paddock.areaHectares,
                yieldTonnes: yieldTonnes,
                yieldPerHa: paddock.areaHectares > 0 ? yieldTonnes / paddock.areaHectares : 0,
                samplesRecorded: recorded.count,
                samplesTotal: sites.count,
                lastUpdated: latestDate
            ))
        }

        return summaries
    }

    private var totalYieldTonnes: Double {
        blockSummaries.reduce(0) { $0 + $1.yieldTonnes }
    }

    private var totalArea: Double {
        blockSummaries.reduce(0) { $0 + $1.areaHa }
    }

    private var filteredHistoricalRecords: [HistoricalYieldRecord] {
        var records = store.historicalYieldRecords

        if let filterId = historicalFilterPaddock {
            records = records.filter { record in
                record.blockResults.contains { $0.paddockId == filterId }
            }
        }

        switch historicalSortBy {
        case .newest:
            records.sort { $0.year > $1.year }
        case .oldest:
            records.sort { $0.year < $1.year }
        case .highestYield:
            records.sort { $0.totalYieldTonnes > $1.totalYieldTonnes }
        case .lowestYield:
            records.sort { $0.totalYieldTonnes < $1.totalYieldTonnes }
        }

        return records
    }

    private var uniquePaddockNames: [(id: UUID, name: String)] {
        var seen = Set<UUID>()
        var result: [(id: UUID, name: String)] = []
        for record in store.historicalYieldRecords {
            for block in record.blockResults {
                if !seen.contains(block.paddockId) {
                    seen.insert(block.paddockId)
                    result.append((id: block.paddockId, name: block.paddockName))
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !blockSummaries.isEmpty {
                    vineyardOverview

                    archiveButton

                    blockSummarySection
                }

                sessionListSection

                historicalSection

                settingsLink
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Yield Reports")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showArchiveSheet) {
            ArchiveYieldSheet(blockSummaries: blockSummaries, totalYieldTonnes: totalYieldTonnes, totalArea: totalArea)
        }
        .sheet(item: $showHistoricalDetail) { record in
            HistoricalYieldDetailSheet(record: record)
        }
    }

    // MARK: - Archive Button

    private var archiveButton: some View {
        Button {
            showArchiveSheet = true
        } label: {
            Label("Archive Current Season", systemImage: "archivebox.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(VineyardTheme.olive)
    }

    // MARK: - Vineyard Overview

    private var vineyardOverview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                overviewCard(
                    title: "Total Yield",
                    value: String(format: "%.2f t", totalYieldTonnes),
                    icon: "scalemass.fill",
                    color: VineyardTheme.leafGreen
                )
                overviewCard(
                    title: "Avg Yield/Ha",
                    value: totalArea > 0 ? String(format: "%.2f t/Ha", totalYieldTonnes / totalArea) : "—",
                    icon: "square.dashed",
                    color: .orange
                )
            }

            HStack(spacing: 12) {
                overviewCard(
                    title: "Blocks",
                    value: "\(blockSummaries.count)",
                    icon: "map.fill",
                    color: .purple
                )
                overviewCard(
                    title: "Total Area",
                    value: String(format: "%.2f Ha", totalArea),
                    icon: "ruler.fill",
                    color: .teal
                )
            }
        }
    }

    private func overviewCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    // MARK: - Block Summary

    private var blockSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Block Summary", systemImage: "chart.bar.xaxis")
                .font(.headline)

            ForEach(blockSummaries, id: \.paddockId) { summary in
                blockSummaryCard(summary)
            }
        }
    }

    private func blockSummaryCard(_ summary: BlockSummary) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.paddockName)
                        .font(.subheadline.weight(.semibold))
                    Text(String(format: "%.2f Ha", summary.areaHa))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f t", summary.yieldTonnes))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(summary.yieldTonnes > 0 ? VineyardTheme.leafGreen : .secondary)
                    if summary.yieldPerHa > 0 {
                        Text(String(format: "%.2f t/Ha", summary.yieldPerHa))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text("\(summary.samplesRecorded)/\(summary.samplesTotal) samples")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if summary.samplesRecorded > 0 {
                    Text(summary.lastUpdated, format: .dateTime.day().month().year())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if summary.samplesTotal > 0 {
                ProgressView(value: Double(summary.samplesRecorded), total: Double(summary.samplesTotal))
                    .tint(summary.samplesRecorded == summary.samplesTotal ? .green : .orange)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    // MARK: - Session List

    private var sessionListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Estimation Jobs", systemImage: "list.bullet.clipboard")
                .font(.headline)

            if sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No yield estimation jobs yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Generate sample sites in Yield Estimation to get started.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(sessions) { session in
                    sessionCard(session)
                }
            }
        }
    }

    private func sessionCard(_ session: YieldEstimationSession) -> some View {
        NavigationLink {
            sessionDetailDestination(session)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionTitle(session))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(session.createdAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 16) {
                    let recorded = session.sampleSites.filter { $0.isRecorded }.count
                    let total = session.sampleSites.count

                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Text("\(recorded)/\(total) samples")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "map")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                        Text("\(session.selectedPaddockIds.count) blocks")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    let yieldT = sessionYield(session)
                    if yieldT > 0 {
                        Text(String(format: "%.2f t", yieldT))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(VineyardTheme.leafGreen)
                    } else {
                        Text("Pending")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                if !session.sampleSites.isEmpty {
                    let recorded = session.sampleSites.filter { $0.isRecorded }.count
                    ProgressView(value: Double(recorded), total: Double(session.sampleSites.count))
                        .tint(recorded == session.sampleSites.count ? .green : .orange)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Historical Section

    private var historicalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Historical Results", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
            }

            if store.historicalYieldRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No historical records")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Archive a completed season to build your yield history.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(HistoricalSort.allCases, id: \.self) { sort in
                            Button {
                                historicalSortBy = sort
                            } label: {
                                Label(sort.label, systemImage: historicalSortBy == sort ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption2.weight(.semibold))
                            Text(historicalSortBy.label)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                    }

                    Menu {
                        Button {
                            historicalFilterPaddock = nil
                        } label: {
                            Label("All Blocks", systemImage: historicalFilterPaddock == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(uniquePaddockNames, id: \.id) { item in
                            Button {
                                historicalFilterPaddock = item.id
                            } label: {
                                Label(item.name, systemImage: historicalFilterPaddock == item.id ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.caption2.weight(.semibold))
                            Text(filterLabel)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                }

                ForEach(filteredHistoricalRecords) { record in
                    Button {
                        showHistoricalDetail = record
                    } label: {
                        historicalRecordCard(record)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.deleteHistoricalYieldRecord(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var filterLabel: String {
        guard let filterId = historicalFilterPaddock,
              let name = uniquePaddockNames.first(where: { $0.id == filterId })?.name else {
            return "All Blocks"
        }
        return name
    }

    private func historicalRecordCard(_ record: HistoricalYieldRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.season.isEmpty ? "\(record.year)" : record.season)
                        .font(.subheadline.weight(.semibold))
                    Text(record.archivedAt, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f t", record.totalYieldTonnes))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(VineyardTheme.leafGreen)
                    if record.totalAreaHectares > 0 {
                        Text(String(format: "%.2f t/Ha", record.yieldPerHectare))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text("\(record.blockResults.count) blocks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "ruler.fill")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                    Text(String(format: "%.2f Ha", record.totalAreaHectares))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    // MARK: - Settings Link

    private var settingsLink: some View {
        NavigationLink {
            YieldSettingsView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(VineyardTheme.leafGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yield Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Default bunch weights per block")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sessionDetailDestination(_ session: YieldEstimationSession) -> some View {
        let vm = YieldEstimationViewModel()
        vm.loadSession(session)
        return YieldReportView(viewModel: vm)
    }

    private func sessionTitle(_ session: YieldEstimationSession) -> String {
        let blockNames = session.selectedPaddockIds.compactMap { pid in
            paddocks.first(where: { $0.id == pid })?.name
        }
        if blockNames.isEmpty {
            return "Yield Estimation"
        } else if blockNames.count <= 3 {
            return blockNames.joined(separator: ", ")
        } else {
            return "\(blockNames.prefix(2).joined(separator: ", ")) +\(blockNames.count - 2) more"
        }
    }

    private func sessionYield(_ session: YieldEstimationSession) -> Double {
        let recorded = session.sampleSites.filter { $0.isRecorded }
        guard !recorded.isEmpty else { return 0 }

        var totalYieldKg: Double = 0

        let grouped = Dictionary(grouping: session.sampleSites, by: \.paddockId)
        for (paddockId, sites) in grouped {
            let recordedSites = sites.filter { $0.isRecorded }
            guard !recordedSites.isEmpty else { continue }

            guard let paddock = paddocks.first(where: { $0.id == paddockId }) else { continue }

            let avgBunches = recordedSites.reduce(0.0) { $0 + ($1.bunchCountEntry?.bunchesPerVine ?? 0) } / Double(recordedSites.count)
            let avgBunchesRounded = (avgBunches * 100).rounded() / 100
            let totalVines = paddock.effectiveVineCount
            let totalBunches = Double(totalVines) * avgBunchesRounded
            let dmgFactor = store.damageFactor(for: paddockId)
            totalYieldKg += totalBunches * session.bunchWeightKg(for: paddockId) * dmgFactor
        }

        return totalYieldKg / 1000.0
    }
}

// MARK: - Supporting Types

private struct BlockSummary {
    let paddockId: UUID
    let paddockName: String
    let areaHa: Double
    let yieldTonnes: Double
    let yieldPerHa: Double
    let samplesRecorded: Int
    let samplesTotal: Int
    let lastUpdated: Date
}

private enum HistoricalSort: String, CaseIterable {
    case newest
    case oldest
    case highestYield
    case lowestYield

    var label: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .highestYield: "Highest Yield"
        case .lowestYield: "Lowest Yield"
        }
    }
}

// MARK: - Archive Sheet

private struct ArchiveYieldSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var season: String = ""
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var notes: String = ""

    let blockSummaries: [BlockSummary]
    let totalYieldTonnes: Double
    let totalArea: Double

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Year")
                        Spacer()
                        TextField("Year", value: $year, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    TextField("Season Name (optional)", text: $season)
                } header: {
                    Text("Season")
                } footer: {
                    Text("e.g. \"2024/25 Vintage\" or leave blank for just the year.")
                }

                Section {
                    HStack {
                        Text("Total Yield")
                        Spacer()
                        Text(String(format: "%.2f t", totalYieldTonnes))
                            .foregroundStyle(VineyardTheme.leafGreen)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Total Area")
                        Spacer()
                        Text(String(format: "%.2f Ha", totalArea))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Blocks")
                        Spacer()
                        Text("\(blockSummaries.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Summary")
                }

                Section {
                    ForEach(blockSummaries, id: \.paddockId) { summary in
                        HStack {
                            Text(summary.paddockName)
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2f t", summary.yieldTonnes))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(VineyardTheme.leafGreen)
                        }
                    }
                } header: {
                    Text("Block Results")
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("Archive Season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        archiveSeason()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func archiveSeason() {
        guard let vid = store.selectedVineyardId else { return }

        let blockResults = blockSummaries.map { summary in
            HistoricalBlockResult(
                paddockId: summary.paddockId,
                paddockName: summary.paddockName,
                areaHectares: summary.areaHa,
                yieldTonnes: summary.yieldTonnes,
                yieldPerHectare: summary.yieldPerHa,
                averageBunchesPerVine: 0,
                averageBunchWeightGrams: 0,
                totalVines: 0,
                samplesRecorded: summary.samplesRecorded,
                damageFactor: 1.0
            )
        }

        let record = HistoricalYieldRecord(
            vineyardId: vid,
            season: season,
            year: year,
            blockResults: blockResults,
            totalYieldTonnes: totalYieldTonnes,
            totalAreaHectares: totalArea,
            notes: notes
        )

        store.addHistoricalYieldRecord(record)
    }
}

// MARK: - Historical Detail Sheet

private struct HistoricalYieldDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: HistoricalYieldRecord

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            detailCard(
                                title: "Total Yield",
                                value: String(format: "%.2f t", record.totalYieldTonnes),
                                icon: "scalemass.fill",
                                color: VineyardTheme.leafGreen
                            )
                            detailCard(
                                title: "Yield/Ha",
                                value: record.totalAreaHectares > 0 ? String(format: "%.2f t/Ha", record.yieldPerHectare) : "—",
                                icon: "square.dashed",
                                color: .orange
                            )
                        }

                        HStack(spacing: 12) {
                            detailCard(
                                title: "Blocks",
                                value: "\(record.blockResults.count)",
                                icon: "map.fill",
                                color: .purple
                            )
                            detailCard(
                                title: "Total Area",
                                value: String(format: "%.2f Ha", record.totalAreaHectares),
                                icon: "ruler.fill",
                                color: .teal
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Block Results", systemImage: "chart.bar.doc.horizontal")
                            .font(.headline)

                        ForEach(record.blockResults) { block in
                            VStack(spacing: 8) {
                                HStack {
                                    Text(block.paddockName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(String(format: "%.2f t", block.yieldTonnes))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(VineyardTheme.leafGreen)
                                }

                                HStack {
                                    Text(String(format: "%.2f Ha", block.areaHectares))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if block.areaHectares > 0 {
                                        Text(String(format: "%.2f t/Ha", block.yieldPerHectare))
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.orange)
                                    }
                                }

                                if block.samplesRecorded > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                        Text("\(block.samplesRecorded) samples")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                        }
                    }

                    if !record.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notes", systemImage: "note.text")
                                .font(.headline)

                            Text(record.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle(record.season.isEmpty ? "\(record.year)" : record.season)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}
