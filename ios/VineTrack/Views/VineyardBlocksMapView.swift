import SwiftUI
import MapKit

nonisolated enum BlockInfoField: String, CaseIterable, Identifiable, Hashable {
    case area
    case vines
    case trellis
    case rows
    case rowSpacing
    case emitterRate
    case emitterSpacing
    case blockLph
    case lPerHa

    var id: String { rawValue }

    var label: String {
        switch self {
        case .area: return "Area"
        case .vines: return "Vines"
        case .trellis: return "Trellis Length"
        case .rows: return "Rows"
        case .rowSpacing: return "Row Spacing"
        case .emitterRate: return "Emitter L/hr"
        case .emitterSpacing: return "Emitter Spacing"
        case .blockLph: return "Block L/hr"
        case .lPerHa: return "L/ha/hr"
        }
    }

    var icon: String {
        switch self {
        case .area: return "map"
        case .vines: return "leaf"
        case .trellis: return "ruler"
        case .rows: return "line.3.horizontal"
        case .rowSpacing: return "arrow.left.and.right"
        case .emitterRate: return "drop"
        case .emitterSpacing: return "arrow.up.and.down.and.arrow.left.and.right"
        case .blockLph: return "drop.fill"
        case .lPerHa: return "square.grid.2x2"
        }
    }

    func value(for paddock: Paddock) -> String? {
        switch self {
        case .area:
            return String(format: "%.2f ha", paddock.areaHectares)
        case .vines:
            return "\(paddock.effectiveVineCount) vines"
        case .trellis:
            let m = paddock.effectiveTotalRowLength
            return m >= 1000 ? String(format: "%.1fkm", m / 1000) : String(format: "%.0fm", m)
        case .rows:
            return "\(paddock.rows.count) rows"
        case .rowSpacing:
            return String(format: "%.1fm rows", paddock.rowWidth)
        case .emitterRate:
            guard let flow = paddock.flowPerEmitter else { return nil }
            return String(format: "%.1f L/hr em", flow)
        case .emitterSpacing:
            guard let s = paddock.emitterSpacing else { return nil }
            return String(format: "%.1fm em", s)
        case .blockLph:
            guard let lph = paddock.litresPerHour else { return nil }
            return lph >= 1000 ? String(format: "%.1fk L/hr", lph / 1000) : String(format: "%.0f L/hr", lph)
        case .lPerHa:
            guard let lpha = paddock.litresPerHaPerHour else { return nil }
            return lpha >= 1000 ? String(format: "%.1fk L/ha/hr", lpha / 1000) : String(format: "%.0f L/ha/hr", lpha)
        }
    }
}

struct VineyardBlocksMapView: View {
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @Binding var selectedPaddock: Paddock?
    var onAddBlock: (() -> Void)? = nil
    @State private var position: MapCameraPosition = .automatic
    @State private var hasSetInitialPosition: Bool = false
    @State private var showFullScreen: Bool = false
    @State private var showFilterSheet: Bool = false
    @State private var selectedPinNames: Set<String> = []
    @State private var selectedInfoFields: Set<BlockInfoField> = []
    @State private var selectedPin: VinePin?

    private var paddocks: [Paddock] {
        store.orderedPaddocks
    }

    private var uniquePinNames: [String] {
        Array(Set(store.pins.map { $0.buttonName })).sorted()
    }

    private var pinNameColors: [String: String] {
        var map: [String: String] = [:]
        for config in store.repairButtons + store.growthButtons {
            if map[config.name] == nil { map[config.name] = config.color }
        }
        return map
    }

    private var visiblePins: [VinePin] {
        guard !selectedPinNames.isEmpty else { return [] }
        return store.pins.filter { selectedPinNames.contains($0.buttonName) }
    }

    private var activeFilterCount: Int {
        (selectedPinNames.isEmpty ? 0 : 1) + (selectedInfoFields.isEmpty ? 0 : 1)
    }

    private var blockColors: [UUID: Color] {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .red, .cyan, .mint, .indigo, .pink, .teal, .yellow, .brown
        ]
        var map: [UUID: Color] = [:]
        for (i, paddock) in paddocks.enumerated() {
            map[paddock.id] = palette[i % palette.count]
        }
        return map
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                ForEach(paddocks) { paddock in
                    if paddock.polygonPoints.count > 2 {
                        let color = blockColors[paddock.id] ?? .blue
                        MapPolygon(coordinates: paddock.polygonPoints.map { $0.coordinate })
                            .foregroundStyle(color.opacity(0.25))
                            .stroke(color, lineWidth: 2.5)

                        Annotation("", coordinate: paddock.polygonPoints.centroid) {
                            Button {
                                selectedPaddock = paddock
                            } label: {
                                blockLabel(for: paddock, color: color)
                            }
                        }
                    }
                }

                ForEach(visiblePins) { pin in
                    Annotation(pin.buttonName, coordinate: pin.coordinate) {
                        Button {
                            selectedPin = pin
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.fromString(pin.buttonColor).gradient)
                                    .frame(width: 22, height: 22)
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                if pin.isCompleted {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    Circle()
                                        .fill(.white.opacity(0.5))
                                        .frame(width: 7, height: 7)
                                }
                            }
                        }
                    }
                }

                UserAnnotation()
            }
            .mapStyle(.hybrid)
            .clipShape(.rect(cornerRadius: 12))

            VStack(spacing: 8) {
                if let onAddBlock {
                    Button {
                        onAddBlock()
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.blue, in: .circle)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    }
                }

                Button {
                    showFilterSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.title3)
                            .foregroundStyle(activeFilterCount > 0 ? .white : .primary)
                            .padding(8)
                            .background(
                                activeFilterCount > 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial),
                                in: .circle
                            )
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 14, height: 14)
                                .background(Color.white, in: .circle)
                                .offset(x: 2, y: -2)
                        }
                    }
                }

                if paddocks.contains(where: { $0.polygonPoints.count > 2 }) {
                    Button {
                        showFullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                }
            }
            .padding(8)
        }
        .frame(height: 280)
        .sheet(isPresented: $showFilterSheet) {
            BlocksMapFilterSheet(
                selectedPinNames: $selectedPinNames,
                selectedInfoFields: $selectedInfoFields,
                uniquePinNames: uniquePinNames,
                pinNameColors: pinNameColors
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedPin) { pin in
            PinDetailSheet(pin: pin)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenBlocksMapView(
                paddocks: paddocks,
                blockColors: blockColors,
                allPins: store.pins,
                selectedPinNames: $selectedPinNames,
                selectedInfoFields: $selectedInfoFields,
                uniquePinNames: uniquePinNames,
                pinNameColors: pinNameColors,
                onSelectPaddock: { selectedPaddock = $0 },
                onSelectPin: { selectedPin = $0 }
            )
        }
        .onAppear {
            locationService.requestPermission()
            locationService.startUpdating()
            fitInitialPosition()
        }
        .onChange(of: locationService.location) { _, newLocation in
            if !hasSetInitialPosition, let loc = newLocation {
                if paddocks.allSatisfy({ $0.polygonPoints.count < 3 }) {
                    position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 1000))
                    hasSetInitialPosition = true
                }
            }
        }
    }

    @ViewBuilder
    private func blockLabel(for paddock: Paddock, color: Color) -> some View {
        let infoLines = selectedInfoFields
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { $0.value(for: paddock) }

        VStack(spacing: 1) {
            Text(paddock.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
            ForEach(infoLines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.85), in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }

    private func fitInitialPosition() {
        let blocksWithBounds = paddocks.filter { $0.polygonPoints.count > 2 }
        guard !blocksWithBounds.isEmpty else {
            if let loc = locationService.location {
                position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 1000))
                hasSetInitialPosition = true
            }
            return
        }
        fitAllBlocks()
        hasSetInitialPosition = true
    }

    private func fitAllBlocks() {
        let allPoints = paddocks.flatMap { $0.polygonPoints }
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
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

struct FullScreenBlocksMapView: View {
    let paddocks: [Paddock]
    let blockColors: [UUID: Color]
    let allPins: [VinePin]
    @Binding var selectedPinNames: Set<String>
    @Binding var selectedInfoFields: Set<BlockInfoField>
    let uniquePinNames: [String]
    let pinNameColors: [String: String]
    let onSelectPaddock: (Paddock) -> Void
    let onSelectPin: (VinePin) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var showFilterSheet: Bool = false

    private var pins: [VinePin] {
        guard !selectedPinNames.isEmpty else { return [] }
        return allPins.filter { selectedPinNames.contains($0.buttonName) }
    }

    private var infoFields: Set<BlockInfoField> { selectedInfoFields }

    private var activeFilterCount: Int {
        (selectedPinNames.isEmpty ? 0 : 1) + (selectedInfoFields.isEmpty ? 0 : 1)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $position) {
                    ForEach(paddocks) { paddock in
                        if paddock.polygonPoints.count > 2 {
                            let color = blockColors[paddock.id] ?? .blue
                            MapPolygon(coordinates: paddock.polygonPoints.map { $0.coordinate })
                                .foregroundStyle(color.opacity(0.25))
                                .stroke(color, lineWidth: 2.5)

                            Annotation("", coordinate: paddock.polygonPoints.centroid) {
                                Button {
                                    onSelectPaddock(paddock)
                                    dismiss()
                                } label: {
                                    blockLabel(for: paddock, color: color)
                                }
                            }
                        }
                    }

                    ForEach(pins) { pin in
                        Annotation(pin.buttonName, coordinate: pin.coordinate) {
                            Button {
                                onSelectPin(pin)
                                dismiss()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.fromString(pin.buttonColor).gradient)
                                        .frame(width: 28, height: 28)
                                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                    if pin.isCompleted {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                    } else {
                                        Circle()
                                            .fill(.white.opacity(0.5))
                                            .frame(width: 9, height: 9)
                                    }
                                }
                            }
                        }
                    }

                    UserAnnotation()
                }
                .mapStyle(.hybrid)
                .ignoresSafeArea()

                Button {
                    showFilterSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.title3)
                            .foregroundStyle(activeFilterCount > 0 ? .white : .primary)
                            .padding(10)
                            .background(
                                activeFilterCount > 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial),
                                in: .circle
                            )
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 14, height: 14)
                                .background(Color.white, in: .circle)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .padding(12)
            }
            .navigationTitle("Blocks Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                BlocksMapFilterSheet(
                    selectedPinNames: $selectedPinNames,
                    selectedInfoFields: $selectedInfoFields,
                    uniquePinNames: uniquePinNames,
                    pinNameColors: pinNameColors
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onAppear { fitAllBlocks() }
        }
    }

    @ViewBuilder
    private func blockLabel(for paddock: Paddock, color: Color) -> some View {
        let infoLines = infoFields
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { $0.value(for: paddock) }

        VStack(spacing: 1) {
            Text(paddock.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
            ForEach(infoLines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.85), in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }

    private func fitAllBlocks() {
        let allPoints = paddocks.flatMap { $0.polygonPoints }
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
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Filter Sheet

struct BlocksMapFilterSheet: View {
    @Binding var selectedPinNames: Set<String>
    @Binding var selectedInfoFields: Set<BlockInfoField>
    let uniquePinNames: [String]
    let pinNameColors: [String: String]
    @Environment(\.dismiss) private var dismiss

    private var hasActive: Bool {
        !selectedPinNames.isEmpty || !selectedInfoFields.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if uniquePinNames.isEmpty {
                        Text("No pins dropped yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Button {
                                selectedPinNames = Set(uniquePinNames)
                            } label: {
                                Text("Select All")
                                    .font(.caption.weight(.semibold))
                            }
                            Spacer()
                            Button {
                                selectedPinNames = []
                            } label: {
                                Text("Clear")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(uniquePinNames, id: \.self) { name in
                            Button {
                                if selectedPinNames.contains(name) {
                                    selectedPinNames.remove(name)
                                } else {
                                    selectedPinNames.insert(name)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.fromString(pinNameColors[name] ?? "gray").gradient)
                                        .frame(width: 18, height: 18)
                                    Text(name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selectedPinNames.contains(name) ? "checkmark.square.fill" : "square")
                                        .font(.title3)
                                        .foregroundStyle(selectedPinNames.contains(name) ? Color.accentColor : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.red)
                        Text("Show Pins")
                    }
                } footer: {
                    Text("Tick the pin types you want to display on the map.")
                }

                Section {
                    HStack {
                        Button {
                            selectedInfoFields = Set(BlockInfoField.allCases)
                        } label: {
                            Text("Select All")
                                .font(.caption.weight(.semibold))
                        }
                        Spacer()
                        Button {
                            selectedInfoFields = []
                        } label: {
                            Text("Clear")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(BlockInfoField.allCases) { field in
                        Button {
                            if selectedInfoFields.contains(field) {
                                selectedInfoFields.remove(field)
                            } else {
                                selectedInfoFields.insert(field)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: field.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                Text(field.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selectedInfoFields.contains(field) ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundStyle(selectedInfoFields.contains(field) ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("Display on Blocks")
                    }
                } footer: {
                    Text("Selected details will appear under each block's name on the map.")
                }
            }
            .navigationTitle("Map Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hasActive {
                        Button("Reset") {
                            selectedPinNames = []
                            selectedInfoFields = []
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
