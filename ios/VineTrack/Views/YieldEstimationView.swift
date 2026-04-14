import SwiftUI
import MapKit

struct YieldEstimationView: View {
    @Environment(DataStore.self) private var store
    @State private var viewModel = YieldEstimationViewModel()
    @State private var mapPosition: MapCameraPosition = .automatic

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
                    sampleListSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Yield Estimation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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

            ForEach(viewModel.sampleSites) { site in
                let paddock = paddocks.first { $0.id == site.paddockId }
                let color = paddock.map { colorFor($0) } ?? .red

                Annotation("", coordinate: site.coordinate) {
                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                        Circle()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                        Text("\(site.siteIndex)")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(color)
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
                        HStack(spacing: 10) {
                            Text("#\(site.siteIndex)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(color)
                                .frame(width: 30, alignment: .trailing)

                            Text("Row \(site.rowNumber)")
                                .font(.caption)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(String(format: "%.5f, %.5f", site.latitude, site.longitude))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            }
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
