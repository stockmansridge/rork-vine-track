import SwiftUI
import MapKit

struct YieldEstimationView: View {
    @Environment(DataStore.self) private var store
    @State private var viewModel = YieldEstimationViewModel()
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showBunchCountSheet: Bool = false
    @State private var showBunchWeightEditor: Bool = false
    @State private var showReport: Bool = false
    @State private var bunchWeightText: String = "150"

    private var paddocks: [Paddock] {
        store.orderedPaddocks.filter { $0.polygonPoints.count >= 3 }
    }

    private var samplesPerHa: Int {
        store.settings.samplesPerHectare
    }

    private let blockColors: [Color] = [
        .blue, .green, .orange, .purple, .red, .cyan, .mint, .indigo, .pink, .teal, .yellow, .brown
    ]

    private func colorFor(_ paddock: Paddock) -> Color {
        guard let idx = paddocks.firstIndex(where: { $0.id == paddock.id }) else { return .blue }
        return blockColors[idx % blockColors.count]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                mapSection
                blockSelectionSection
                summarySection
                generateButton

                if viewModel.isGenerated {
                    pathButton
                    bunchWeightButton

                    if viewModel.recordedSiteCount > 0 {
                        reportButton
                    }

                    progressSection
                    sampleListSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Yield Estimation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBunchCountSheet) {
            if let site = viewModel.selectedSite {
                BunchCountEntrySheet(site: site) { count, name in
                    viewModel.recordBunchCount(siteId: site.id, bunchesPerVine: count, recordedBy: name)
                    saveSession()
                }
            }
        }
        .sheet(isPresented: $showBunchWeightEditor) {
            bunchWeightSheet
        }
        .navigationDestination(isPresented: $showReport) {
            YieldReportView(viewModel: viewModel)
        }
        .onAppear {
            loadExistingSession()
            fitMap()
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $mapPosition) {
            ForEach(paddocks) { paddock in
                let color = colorFor(paddock)
                let isSelected = viewModel.selectedPaddockIds.contains(paddock.id)

                MapPolygon(coordinates: paddock.polygonPoints.map(\.coordinate))
                    .foregroundStyle(color.opacity(isSelected ? 0.3 : 0.08))
                    .stroke(color.opacity(isSelected ? 1.0 : 0.3), lineWidth: isSelected ? 2.5 : 1)

                if isSelected {
                    ForEach(paddock.rows) { row in
                        MapPolyline(coordinates: [row.startPoint.coordinate, row.endPoint.coordinate])
                            .stroke(color.opacity(0.2), lineWidth: 0.5)
                    }
                }

                Annotation("", coordinate: paddock.polygonPoints.centroid) {
                    Text(paddock.name)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(isSelected ? 0.9 : 0.4), in: .capsule)
                }
            }

            if viewModel.isPathGenerated {
                MapPolyline(coordinates: viewModel.pathWaypoints.map(\.coordinate))
                    .stroke(.orange, lineWidth: 2.5)
            }

            ForEach(viewModel.sampleSites) { site in
                let paddock = paddocks.first { $0.id == site.paddockId }
                let color = paddock.map { colorFor($0) } ?? .red
                let isRecorded = site.isRecorded

                Annotation("", coordinate: site.coordinate) {
                    Button {
                        viewModel.selectedSite = site
                        showBunchCountSheet = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecorded ? .green : color)
                                .frame(width: 24, height: 24)
                            Circle()
                                .fill(.white)
                                .frame(width: 16, height: 16)
                            if isRecorded {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.green)
                            } else {
                                Text("\(site.siteIndex)")
                                    .font(.system(size: 7, weight: .heavy))
                                    .foregroundStyle(color)
                            }
                        }
                    }
                }
            }
        }
        .mapStyle(.hybrid)
        .frame(height: 320)
        .clipShape(.rect(cornerRadius: 14))
    }

    // MARK: - Block Selection

    private var blockSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Select Blocks", systemImage: "checklist")
                    .font(.headline)

                Spacer()

                if viewModel.selectedPaddockIds.count == paddocks.count {
                    Button("Deselect All") {
                        viewModel.deselectAll()
                    }
                    .font(.caption.weight(.medium))
                } else {
                    Button("Select All") {
                        viewModel.selectAll(paddocks: paddocks)
                    }
                    .font(.caption.weight(.medium))
                }
            }

            if paddocks.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No blocks with boundaries found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(paddocks) { paddock in
                        let isSelected = viewModel.selectedPaddockIds.contains(paddock.id)
                        let color = colorFor(paddock)

                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                viewModel.togglePaddock(paddock.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(isSelected ? color : .secondary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(paddock.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(String(format: "%.2f Ha", paddock.areaHectares))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected ? color.opacity(0.12) : Color(.tertiarySystemFill))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? color.opacity(0.5) : .clear, lineWidth: 1.5)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Group {
            if !viewModel.selectedPaddockIds.isEmpty {
                let totalArea = viewModel.totalSelectedArea(paddocks: paddocks)
                let expectedSamples = viewModel.expectedSampleCount(paddocks: paddocks, samplesPerHectare: samplesPerHa)

                HStack(spacing: 0) {
                    summaryCard(
                        title: "Area",
                        value: String(format: "%.2f Ha", totalArea),
                        icon: "square.dashed",
                        color: VineyardTheme.leafGreen
                    )
                    summaryCard(
                        title: "Samples/Ha",
                        value: "\(samplesPerHa)",
                        icon: "number",
                        color: .orange
                    )
                    summaryCard(
                        title: "Total Sites",
                        value: "\(expectedSamples)",
                        icon: "mappin.and.ellipse",
                        color: .purple
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                viewModel.generateSampleSites(paddocks: paddocks, samplesPerHectare: samplesPerHa)
            }
            fitMapToSites()
            saveSession()
        } label: {
            Label(
                viewModel.isGenerated ? "Regenerate Sample Sites" : "Generate Sample Sites",
                systemImage: viewModel.isGenerated ? "arrow.clockwise" : "mappin.and.ellipse"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(VineyardTheme.leafGreen)
        .disabled(viewModel.selectedPaddockIds.isEmpty)
    }

    // MARK: - Path Button

    private var pathButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                viewModel.generatePath(paddocks: paddocks)
            }
            fitMapToSites()
            saveSession()
        } label: {
            Label(
                viewModel.isPathGenerated ? "Regenerate Path" : "Generate Path",
                systemImage: viewModel.isPathGenerated ? "arrow.triangle.turn.up.right.circle" : "point.topleft.down.to.point.bottomright.curvepath"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }

    // MARK: - Bunch Weight

    private var bunchWeightButton: some View {
        Button {
            bunchWeightText = String(format: "%.0f", viewModel.averageBunchWeightKg * 1000)
            showBunchWeightEditor = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "scalemass.fill")
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Average Bunch Weight")
                        .font(.subheadline.weight(.medium))
                    Text(String(format: "%.0f g (%.3f kg)", viewModel.averageBunchWeightKg * 1000, viewModel.averageBunchWeightKg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Report Button

    private var reportButton: some View {
        Button {
            showReport = true
        } label: {
            Label("View Yield Report", systemImage: "chart.bar.doc.horizontal.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Collection Progress", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.recordedSiteCount)/\(viewModel.totalSiteCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.recordedSiteCount == viewModel.totalSiteCount ? .green : .orange)
            }

            if viewModel.totalSiteCount > 0 {
                ProgressView(value: Double(viewModel.recordedSiteCount), total: Double(viewModel.totalSiteCount))
                    .tint(viewModel.recordedSiteCount == viewModel.totalSiteCount ? .green : .orange)
            }
        }
    }

    // MARK: - Sample List

    private var sampleListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(viewModel.sampleSites.count) Sample Sites", systemImage: "list.number")
                    .font(.headline)
                Spacer()
            }

            let grouped = Dictionary(grouping: viewModel.sampleSites, by: \.paddockId)
            let sortedKeys = paddocks.filter { grouped[$0.id] != nil }

            ForEach(sortedKeys) { paddock in
                let sites = grouped[paddock.id] ?? []
                let color = colorFor(paddock)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                        Text(paddock.name)
                            .font(.subheadline.weight(.semibold))
                        Text("(\(sites.count) sites)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(sites) { site in
                        Button {
                            viewModel.selectedSite = site
                            showBunchCountSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Text("#\(site.siteIndex)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(color)
                                    .frame(width: 30, alignment: .trailing)

                                Text("Row \(site.rowNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)

                                if let entry = site.bunchCountEntry {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                        Text(String(format: "%.1f bunches", entry.bunchesPerVine))
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.green)
                                    }
                                }

                                Spacer()

                                if site.isRecorded {
                                    if let entry = site.bunchCountEntry {
                                        Text(entry.recordedBy)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                } else {
                                    Text("Tap to record")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            }
        }
    }

    // MARK: - Bunch Weight Sheet

    private var bunchWeightSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Weight in grams", text: $bunchWeightText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Average Bunch Weight (grams)")
                } footer: {
                    Text("Enter the average bunch weight in grams. This value is used in the yield calculation.")
                }

                if !viewModel.previousBunchWeights.isEmpty {
                    Section {
                        ForEach(viewModel.previousBunchWeights.sorted(by: { $0.date > $1.date }).prefix(5)) { record in
                            Button {
                                bunchWeightText = String(format: "%.0f", record.weightKg * 1000)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.date, format: .dateTime.day().month().year())
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(String(format: "%.0f g", record.weightKg * 1000))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.uturn.left")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Previous Records")
                    }
                }
            }
            .navigationTitle("Bunch Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBunchWeightEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let grams = Double(bunchWeightText), grams > 0 {
                            let kg = grams / 1000.0
                            viewModel.averageBunchWeightKg = kg
                            let record = BunchWeightRecord(date: Date(), weightKg: kg)
                            viewModel.previousBunchWeights.append(record)
                            saveSession()
                        }
                        showBunchWeightEditor = false
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(bunchWeightText) == nil || (Double(bunchWeightText) ?? 0) <= 0)
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveSession() {
        guard let vid = store.selectedVineyardId else { return }
        let session = viewModel.toSession(vineyardId: vid, samplesPerHectare: samplesPerHa)
        store.saveYieldSession(session)
    }

    private func loadExistingSession() {
        guard let vid = store.selectedVineyardId else { return }
        if let session = store.yieldSessions.first(where: { $0.vineyardId == vid }) {
            viewModel.loadSession(session)
        }
    }

    // MARK: - Map Helpers

    private func fitMap() {
        let allPoints = paddocks.flatMap(\.polygonPoints)
        guard !allPoints.isEmpty else { return }

        let minLat = allPoints.map(\.latitude).min()!
        let maxLat = allPoints.map(\.latitude).max()!
        let minLon = allPoints.map(\.longitude).min()!
        let maxLon = allPoints.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 0.001,
            longitudeDelta: (maxLon - minLon) * 1.4 + 0.001
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func fitMapToSites() {
        guard !viewModel.sampleSites.isEmpty else {
            fitMap()
            return
        }

        let selectedPaddockPoints = paddocks
            .filter { viewModel.selectedPaddockIds.contains($0.id) }
            .flatMap(\.polygonPoints)

        let allLats = selectedPaddockPoints.map(\.latitude) + viewModel.sampleSites.map(\.latitude)
        let allLons = selectedPaddockPoints.map(\.longitude) + viewModel.sampleSites.map(\.longitude)

        guard let minLat = allLats.min(), let maxLat = allLats.max(),
              let minLon = allLons.min(), let maxLon = allLons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 0.001,
            longitudeDelta: (maxLon - minLon) * 1.4 + 0.001
        )
        withAnimation(.smooth(duration: 0.4)) {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
