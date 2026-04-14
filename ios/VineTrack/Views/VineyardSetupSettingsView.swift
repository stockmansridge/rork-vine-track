import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

struct VineyardSetupSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @State private var showAddPaddock: Bool = false
    @State private var editingPaddock: Paddock?
    @State private var showEditRepairButtons: Bool = false
    @State private var showEditGrowthButtons: Bool = false
    @State private var showRepairTemplates: Bool = false
    @State private var showGrowthTemplates: Bool = false
    @State private var showGrowthStageConfig: Bool = false
    @State private var weatherStationService = WeatherStationService()
    @State private var manualStationId: String = ""
    @State private var showStationPicker: Bool = false
    @State private var showExportShare: Bool = false
    @State private var exportFileURL: URL?
    @State private var showImportPicker: Bool = false
    @State private var showImportPreview: Bool = false
    @State private var importData: BlockExportData?
    @State private var importError: String?

    @State private var mapSelectedPaddock: Paddock?

    var body: some View {
        Form {
            vineyardMapSection
            paddocksSection
            blockExportImportSection
            buttonsSection
            growthStageSection
            weatherStationSection
        }
        .navigationTitle("Vineyard Setup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            manualStationId = store.settings.weatherStationId ?? ""
        }
        .sheet(isPresented: $showStationPicker) {
            NearbyStationPicker(weatherStationService: weatherStationService, onSelect: { stationId in
                manualStationId = stationId
                var s = store.settings
                s.weatherStationId = stationId
                store.updateSettings(s)
                showStationPicker = false
            })
        }
        .sheet(isPresented: $showAddPaddock) {
            EditPaddockSheet(paddock: nil)
        }
        .sheet(item: $editingPaddock) { paddock in
            EditPaddockSheet(paddock: paddock)
        }
        .onChange(of: mapSelectedPaddock) { _, newValue in
            if let paddock = newValue {
                mapSelectedPaddock = nil
                editingPaddock = paddock
            }
        }
        .sheet(isPresented: $showEditRepairButtons) {
            EditButtonsSheet(mode: .repairs)
        }
        .sheet(isPresented: $showEditGrowthButtons) {
            EditButtonsSheet(mode: .growth)
        }
        .sheet(isPresented: $showRepairTemplates) {
            ButtonTemplateListView(mode: .repairs)
        }
        .sheet(isPresented: $showGrowthTemplates) {
            ButtonTemplateListView(mode: .growth)
        }
        .sheet(isPresented: $showGrowthStageConfig) {
            GrowthStageConfigSheet()
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    importData = try BlockExportImportService.parseImportData(data)
                    showImportPreview = true
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showImportPreview) {
            if let importData {
                BlockImportView(importData: importData)
            }
        }
        .alert("Import Error", isPresented: .init(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var vineyardMapSection: some View {
        Section {
            if store.orderedPaddocks.contains(where: { $0.polygonPoints.count > 2 }) {
                VineyardBlocksMapView(selectedPaddock: $mapSelectedPaddock, onAddBlock: { showAddPaddock = true })
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No block boundaries defined yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add blocks with boundary points to see them on the map.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text("Vineyard Map")
            }
        } footer: {
            if store.orderedPaddocks.contains(where: { $0.polygonPoints.count > 2 }) {
                Text("Tap a block on the map to edit its settings.")
            }
        }
    }

    private var paddocksSection: some View {
        Section {
            ForEach(store.orderedPaddocks) { paddock in
                Button {
                    editingPaddock = paddock
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(paddock.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            let rowNumbers = paddock.rows.map { $0.number }.sorted()
                            if let first = rowNumbers.first, let last = rowNumbers.last {
                                Text("Row \(first) to Row \(last) \u{2022} \(paddock.rows.count) rows \u{2022} \(paddock.effectiveVineCount) vines")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(paddock.rows.count) rows \u{2022} \(paddock.polygonPoints.count) boundary points")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deletePaddock(paddock)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                var ordered = store.orderedPaddocks
                ordered.move(fromOffsets: source, toOffset: destination)
                store.updatePaddockOrder(ordered.map { $0.id })
            }

        } header: {
            Text("Blocks")
        } footer: {
            Text("Define block boundaries and row layouts for your vineyard.")
        }
    }

    private var blockExportImportSection: some View {
        Section {
            Button {
                exportBlocks()
            } label: {
                HStack {
                    Label("Export Blocks", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(store.paddocks.count) blocks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .disabled(store.paddocks.isEmpty)

            Button {
                showImportPicker = true
            } label: {
                HStack {
                    Label("Import Blocks", systemImage: "square.and.arrow.down")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Export / Import")
        } footer: {
            Text("Export your block data as JSON to share or back up. Import blocks from a previously exported file.")
        }
    }

    private func exportBlocks() {
        guard let vineyard = store.selectedVineyard else { return }
        do {
            let data = try BlockExportImportService.exportBlocks(
                paddocks: store.paddocks,
                vineyardName: vineyard.name
            )
            exportFileURL = try BlockExportImportService.exportFileURL(
                vineyardName: vineyard.name,
                data: data
            )
            showExportShare = true
        } catch {
            importError = "Export failed: \(error.localizedDescription)"
        }
    }

    private var buttonsSection: some View {
        Section {
            Button {
                showEditRepairButtons = true
            } label: {
                HStack {
                    Label("Repair Buttons", systemImage: "wrench")
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(store.repairButtons.prefix(4)) { btn in
                            Circle()
                                .fill(Color.fromString(btn.color))
                                .frame(width: 10, height: 10)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                showRepairTemplates = true
            } label: {
                HStack {
                    Label("Repair Templates", systemImage: "square.on.square")
                        .foregroundStyle(.primary)
                    Spacer()
                    let count = store.buttonTemplates(for: .repairs).count
                    if count > 0 {
                        Text("\(count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                showEditGrowthButtons = true
            } label: {
                HStack {
                    Label("Growth Buttons", systemImage: "leaf")
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(store.growthButtons.prefix(4)) { btn in
                            Circle()
                                .fill(Color.fromString(btn.color))
                                .frame(width: 10, height: 10)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                showGrowthTemplates = true
            } label: {
                HStack {
                    Label("Growth Templates", systemImage: "square.on.square")
                        .foregroundStyle(.primary)
                    Spacer()
                    let count = store.buttonTemplates(for: .growth).count
                    if count > 0 {
                        Text("\(count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Button Customization")
        } footer: {
            Text("Customize buttons directly or create templates to quickly switch between different button sets. Templates pair rows left and right.")
        }
    }

    private var weatherStationSection: some View {
        Section {
            HStack {
                Label("Station ID", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("e.g. KCASTATI123", text: $manualStationId)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(.secondary)
                    .onSubmit {
                        let trimmed = manualStationId.trimmingCharacters(in: .whitespacesAndNewlines)
                        var s = store.settings
                        s.weatherStationId = trimmed.isEmpty ? nil : trimmed
                        store.updateSettings(s)
                    }
            }

            if let stationId = store.settings.weatherStationId, !stationId.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VineyardTheme.leafGreen)
                    Text("Using station **\(stationId)**")
                        .font(.subheadline)
                    Spacer()
                    Button("Clear") {
                        manualStationId = ""
                        var s = store.settings
                        s.weatherStationId = nil
                        store.updateSettings(s)
                    }
                    .font(.subheadline)
                }
            }

            Button {
                if let location = locationService.location {
                    showStationPicker = true
                    Task {
                        await weatherStationService.fetchNearbyStations(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    }
                } else {
                    locationService.requestPermission()
                    locationService.startUpdating()
                }
            } label: {
                HStack {
                    Label("Find Nearest Station", systemImage: "location.magnifyingglass")
                    Spacer()
                    if locationService.location == nil {
                        Text("Requires Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Weather Station")
            }
        } footer: {
            Text("Enter your Weather Underground PWS Station ID, or find the nearest station to your location.")
        }
    }

    private var growthStageSection: some View {
        Section {
            Button {
                showGrowthStageConfig = true
            } label: {
                HStack {
                    Label("E-L Growth Stages", systemImage: "leaf.arrow.triangle.circlepath")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(store.settings.enabledGrowthStageCodes.count)/\(GrowthStage.allStages.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Growth Stages")
        } footer: {
            Text("Configure which E-L growth stages are available when dropping a Growth Stage pin.")
        }
    }
}
