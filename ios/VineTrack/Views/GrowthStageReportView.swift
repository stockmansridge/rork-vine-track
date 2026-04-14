import SwiftUI

struct GrowthStageReportView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.accessControl) private var accessControl
    @State private var selectedVintages: Set<Int> = []
    @State private var selectedPaddockId: UUID?
    @State private var showShareSheet: Bool = false
    @State private var pdfURL: URL?

    private var seasonStartMonth: Int { store.settings.seasonStartMonth }
    private var seasonStartDay: Int { store.settings.seasonStartDay }

    private var growthPins: [VinePin] {
        store.pins.filter { $0.growthStageCode != nil && $0.mode == .growth }
    }

    private var filteredPins: [VinePin] {
        var pins = growthPins
        if let paddockId = selectedPaddockId {
            pins = pins.filter { $0.paddockId == paddockId }
        }
        return pins
    }

    private var availableVintages: [Int] {
        let vintages = Set(filteredPins.map { vintageYear(for: $0.timestamp) })
        return vintages.sorted(by: >)
    }

    private var activeVintages: [Int] {
        if selectedVintages.isEmpty {
            return availableVintages
        }
        return availableVintages.filter { selectedVintages.contains($0) }
    }

    private var allStageCodes: [String] {
        let enabledCodes = store.settings.enabledGrowthStageCodes
        let usedCodes = Set(filteredPins.compactMap { $0.growthStageCode })
        let allCodes = Set(enabledCodes).union(usedCodes)
        return GrowthStage.allStages
            .map { $0.code }
            .filter { allCodes.contains($0) }
    }

    private func vintageYear(for date: Date) -> Int {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let year = cal.component(.year, from: date)

        if month > seasonStartMonth || (month == seasonStartMonth && day >= seasonStartDay) {
            return year + 1
        }
        return year
    }

    private func vintageRange(for vintage: Int) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let startComponents = DateComponents(year: vintage - 1, month: seasonStartMonth, day: seasonStartDay)
        let endComponents = DateComponents(year: vintage, month: seasonStartMonth, day: seasonStartDay)
        let start = cal.date(from: startComponents) ?? Date()
        let end = cal.date(byAdding: .day, value: -1, to: cal.date(from: endComponents) ?? Date()) ?? Date()
        return (start, end)
    }

    private func endOfDay(_ date: Date) -> Date {
        let cal = Calendar.current
        if let result = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date) {
            return result
        }
        return date
    }

    private func stageEntries(for vintage: Int) -> [String: [VinePin]] {
        let range = vintageRange(for: vintage)
        let rangeEnd = endOfDay(range.end)
        let pins = filteredPins.filter { $0.timestamp >= range.start && $0.timestamp <= rangeEnd }
        var result: [String: [VinePin]] = [:]
        for pin in pins {
            guard let code = pin.growthStageCode else { continue }
            result[code, default: []].append(pin)
        }
        for key in result.keys {
            result[key]?.sort { $0.timestamp < $1.timestamp }
        }
        return result
    }

    private let vintageColors: [Color] = [
        .blue, .green, .orange, .purple, .red, .teal, .pink, .indigo, .mint, .cyan
    ]

    private func colorForVintage(_ vintage: Int) -> Color {
        let sorted = activeVintages.sorted(by: >)
        guard let idx = sorted.firstIndex(of: vintage) else { return .primary }
        return vintageColors[idx % vintageColors.count]
    }

    var body: some View {
        Group {
            if growthPins.isEmpty {
                ContentUnavailableView(
                    "No Growth Data",
                    systemImage: "leaf.arrow.triangle.circlepath",
                    description: Text("Drop growth stage pins from the Home tab to build your vintage report.")
                )
            } else if availableVintages.isEmpty {
                ContentUnavailableView(
                    "No Matching Data",
                    systemImage: "leaf.arrow.triangle.circlepath",
                    description: Text("No growth stage entries found for the selected block.")
                )
            } else {
                List {
                    paddockFilterSection
                    vintageFilterSection
                    reportSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Growth Stage Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !availableVintages.isEmpty && (accessControl?.canExport ?? true) {
                    Button {
                        generatePDF()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let pdfURL {
                ShareSheet(items: [pdfURL])
            }
        }
    }

    private func generatePDF() {
        var blockReports: [GrowthStageReportPDFService.BlockReport] = []

        if let paddockId = selectedPaddockId {
            if let paddock = store.paddocks.first(where: { $0.id == paddockId }) {
                let blockPins = filteredPins
                if let report = buildBlockReport(name: paddock.name, pins: blockPins) {
                    blockReports.append(report)
                }
            }
        } else {
            for paddock in store.paddocks {
                let blockPins = growthPins.filter { $0.paddockId == paddock.id }
                if let report = buildBlockReport(name: paddock.name, pins: blockPins) {
                    blockReports.append(report)
                }
            }

            let unassignedPins = growthPins.filter { $0.paddockId == nil }
            if !unassignedPins.isEmpty {
                if let report = buildBlockReport(name: "Unassigned", pins: unassignedPins) {
                    blockReports.append(report)
                }
            }

            if blockReports.isEmpty {
                if let report = buildBlockReport(name: store.selectedVineyard?.name ?? "All Blocks", pins: growthPins) {
                    blockReports.append(report)
                }
            }
        }

        guard !blockReports.isEmpty else { return }

        var vintageColorMap: [Int: UIColor] = [:]
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemRed, .systemTeal, .systemPink, .systemIndigo, .systemMint, .systemCyan]
        let sortedAll = activeVintages.sorted(by: >)
        for (i, v) in sortedAll.enumerated() {
            vintageColorMap[v] = colors[i % colors.count]
        }

        let pdfData = GrowthStageReportPDFService.generatePDF(
            blocks: blockReports,
            vineyardName: store.selectedVineyard?.name ?? "Vineyard",
            seasonStartMonth: seasonStartMonth,
            seasonStartDay: seasonStartDay,
            vintageColors: vintageColorMap,
            logoData: store.selectedVineyard?.logoData
        )

        let url = GrowthStageReportPDFService.savePDFToTemp(data: pdfData, fileName: "GrowthStageReport_\(store.selectedVineyard?.name ?? "Vineyard")")
        pdfURL = url
        showShareSheet = true
    }

    private func buildBlockReport(name: String, pins: [VinePin]) -> GrowthStageReportPDFService.BlockReport? {
        let blockVintages = Set(pins.map { vintageYear(for: $0.timestamp) })
        let vintages: [Int]
        if selectedVintages.isEmpty {
            vintages = blockVintages.sorted(by: >)
        } else {
            vintages = blockVintages.filter { selectedVintages.contains($0) }.sorted(by: >)
        }
        guard !vintages.isEmpty else { return nil }

        var entries: [Int: [String: Date]] = [:]
        for vintage in vintages {
            let range = vintageRange(for: vintage)
            let rangeEnd = endOfDay(range.end)
            let vintagePins = pins.filter {
                $0.timestamp >= range.start && $0.timestamp <= rangeEnd
            }
            var stageMap: [String: Date] = [:]
            for pin in vintagePins {
                guard let code = pin.growthStageCode else { continue }
                if let existing = stageMap[code] {
                    if pin.timestamp < existing {
                        stageMap[code] = pin.timestamp
                    }
                } else {
                    stageMap[code] = pin.timestamp
                }
            }
            entries[vintage] = stageMap
        }

        return GrowthStageReportPDFService.BlockReport(
            blockName: name,
            vintages: vintages,
            stageCodes: allStageCodes,
            entries: entries
        )
    }

    private var paddockFilterSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: "All Blocks", isSelected: selectedPaddockId == nil) {
                        selectedPaddockId = nil
                    }
                    ForEach(store.paddocks) { paddock in
                        FilterChip(title: paddock.name, isSelected: selectedPaddockId == paddock.id) {
                            selectedPaddockId = selectedPaddockId == paddock.id ? nil : paddock.id
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Block")
        }
    }

    private var vintageFilterSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: "All Vintages", isSelected: selectedVintages.isEmpty) {
                        selectedVintages = []
                    }
                    ForEach(availableVintages, id: \.self) { vintage in
                        Button {
                            if selectedVintages.contains(vintage) {
                                selectedVintages.remove(vintage)
                            } else {
                                selectedVintages.insert(vintage)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(colorForVintage(vintage))
                                    .frame(width: 10, height: 10)
                                Text("Vintage \(String(vintage))")
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedVintages.contains(vintage) ? colorForVintage(vintage).opacity(0.15) : Color(.tertiarySystemBackground))
                            .foregroundStyle(selectedVintages.contains(vintage) ? colorForVintage(vintage) : .primary)
                            .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.purple)
                    .font(.caption)
                Text("Vintages")
            }
        } footer: {
            if let first = availableVintages.first {
                let range = vintageRange(for: first)
                Text("Vintage \(String(first)): \(range.start.formatted(.dateTime.day().month(.abbreviated).year())) \u{2013} \(range.end.formatted(.dateTime.day().month(.abbreviated).year()))")
            }
        }
    }

    private var reportSection: some View {
        Section {
            ForEach(allStageCodes, id: \.self) { code in
                stageRow(for: code)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "leaf.arrow.triangle.circlepath")
                    .foregroundStyle(VineyardTheme.leafGreen)
                    .font(.caption)
                Text("E-L Growth Stages")
            }
        }
    }

    private func stageRow(for code: String) -> some View {
        let stage = GrowthStage.allStages.first { $0.code == code }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(code)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(VineyardTheme.leafGreen.gradient, in: .rect(cornerRadius: 6))

                if let stage {
                    Text(stage.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            ForEach(activeVintages, id: \.self) { vintage in
                vintageRow(for: code, vintage: vintage)
            }
        }
        .padding(.vertical, 4)
    }

    private func vintageRow(for code: String, vintage: Int) -> some View {
        let entries = stageEntries(for: vintage)
        let pins = entries[code] ?? []
        let color = colorForVintage(vintage)

        return Group {
            if !pins.isEmpty {
                ForEach(pins) { pin in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: 3, height: 20)

                        Text(String(vintage))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(color)
                            .frame(width: 38, alignment: .leading)

                        Text(pin.timestamp.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption.monospacedDigit())

                        Spacer()

                        if let paddockId = pin.paddockId,
                           let paddock = store.paddocks.first(where: { $0.id == paddockId }) {
                            Text(paddock.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: .capsule)
                        }
                    }
                }
            } else if selectedVintages.isEmpty || selectedVintages.contains(vintage) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.3))
                        .frame(width: 3, height: 20)

                    Text(String(vintage))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(color.opacity(0.4))
                        .frame(width: 38, alignment: .leading)

                    Text("\u{2014}")
                        .font(.caption)
                        .foregroundStyle(.quaternary)

                    Spacer()
                }
            }
        }
    }
}
