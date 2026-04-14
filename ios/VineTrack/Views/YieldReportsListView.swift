import SwiftUI

struct YieldReportsListView: View {
    @Environment(DataStore.self) private var store

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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !blockSummaries.isEmpty {
                    vineyardOverview
                    blockSummarySection
                }

                sessionListSection
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Yield Reports")
        .navigationBarTitleDisplayMode(.inline)
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
