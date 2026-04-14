import SwiftUI
import MapKit

struct RecordDamageView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let paddock: Paddock

    @State private var polygonPoints: [CoordinatePoint] = []
    @State private var damageDate: Date = Date()
    @State private var damageType: DamageType = .frost
    @State private var damagePercentText: String = "20"
    @State private var notes: String = ""
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var draggingIndex: Int?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showConfirmation: Bool = false

    private var damageAreaHa: Double {
        let points = polygonPoints
        guard points.count >= 3 else { return 0 }
        let centroidLat = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0 * cos(centroidLat * .pi / 180.0)
        var area = 0.0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            let xi = points[i].longitude * mPerDegLon
            let yi = points[i].latitude * mPerDegLat
            let xj = points[j].longitude * mPerDegLon
            let yj = points[j].latitude * mPerDegLat
            area += xi * yj - xj * yi
        }
        area = abs(area) / 2.0
        return area / 10_000.0
    }

    private var damagePercent: Double {
        Double(damagePercentText) ?? 0
    }

    private var isValid: Bool {
        polygonPoints.count >= 3 && damagePercent > 0 && damagePercent <= 100
    }

    private var midpointEdges: [DamageMidpointEdge] {
        guard polygonPoints.count >= 2 else { return [] }
        var edges: [DamageMidpointEdge] = []
        for i in 0..<polygonPoints.count {
            let j = (i + 1) % polygonPoints.count
            if j == 0 && polygonPoints.count < 3 { continue }
            let midLat = (polygonPoints[i].latitude + polygonPoints[j].latitude) / 2
            let midLon = (polygonPoints[i].longitude + polygonPoints[j].longitude) / 2
            let mid = CLLocationCoordinate2D(latitude: midLat, longitude: midLon)
            edges.append(DamageMidpointEdge(id: "\(polygonPoints[i].id)-\(polygonPoints[j].id)", midpoint: mid, insertIndex: i + 1))
        }
        return edges
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                mapSection
                drawingControls
                damageAreaInfo
                damageDetailsSection
                saveButton
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Record Damage")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fitMapToPaddock() }
        .sensoryFeedback(.success, trigger: showConfirmation)
        .alert("Damage Recorded", isPresented: $showConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            Text("Damage of \(Int(damagePercent))% \(damageType.rawValue) has been recorded for \(paddock.name).")
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        MapReader { proxy in
            Map(position: $mapPosition, interactionModes: draggingIndex != nil ? [] : [.pan, .zoom, .pitch, .rotate]) {
                MapPolygon(coordinates: paddock.polygonPoints.map(\.coordinate))
                    .foregroundStyle(.blue.opacity(0.08))
                    .stroke(.blue.opacity(0.6), lineWidth: 2)

                Annotation("", coordinate: paddock.polygonPoints.centroid) {
                    Text(paddock.name)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.8), in: .capsule)
                        .allowsHitTesting(false)
                }

                ForEach(paddock.rows) { row in
                    MapPolyline(coordinates: [row.startPoint.coordinate, row.endPoint.coordinate])
                        .stroke(.blue.opacity(0.15), lineWidth: 0.5)
                }

                let existingDamage = store.damageRecords(for: paddock.id)
                ForEach(existingDamage) { record in
                    if record.polygonPoints.count >= 3 {
                        MapPolygon(coordinates: record.polygonPoints.map(\.coordinate))
                            .foregroundStyle(.red.opacity(0.2))
                            .stroke(.red.opacity(0.6), lineWidth: 1.5)
                    }
                }

                if polygonPoints.count > 2 {
                    MapPolygon(coordinates: polygonPoints.map(\.coordinate))
                        .foregroundStyle(.orange.opacity(0.25))
                        .stroke(.orange, lineWidth: 2.5)
                } else if polygonPoints.count == 2 {
                    MapPolyline(coordinates: polygonPoints.map(\.coordinate))
                        .stroke(.orange, lineWidth: 2.5)
                }

                ForEach(Array(polygonPoints.enumerated()), id: \.element.id) { index, point in
                    Annotation("", coordinate: point.coordinate) {
                        DamagePointHandle(index: index, isDragging: draggingIndex == index)
                            .gesture(
                                DragGesture(coordinateSpace: .global)
                                    .onChanged { value in
                                        draggingIndex = index
                                        if let coord = proxy.convert(value.location, from: .global) {
                                            let existingId = polygonPoints[index].id
                                            polygonPoints[index] = CoordinatePoint(id: existingId, coordinate: coord)
                                        }
                                    }
                                    .onEnded { _ in
                                        draggingIndex = nil
                                    }
                            )
                    }
                }

                ForEach(midpointEdges, id: \.id) { edge in
                    Annotation("", coordinate: edge.midpoint) {
                        DamageMidpointHandle()
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.2)) {
                                    let newPoint = CoordinatePoint(coordinate: edge.midpoint)
                                    polygonPoints.insert(newPoint, at: edge.insertIndex)
                                }
                            }
                    }
                }
            }
            .mapStyle(.hybrid)
            .frame(height: 350)
            .clipShape(.rect(cornerRadius: 14))
            .onTapGesture { screenCoord in
                guard draggingIndex == nil else { return }
                if let coordinate = proxy.convert(screenCoord, from: .local) {
                    withAnimation(.snappy(duration: 0.2)) {
                        polygonPoints.append(CoordinatePoint(coordinate: coordinate))
                    }
                }
            }
        }
    }

    // MARK: - Drawing Controls

    private var drawingControls: some View {
        VStack(spacing: 10) {
            Text(polygonPoints.isEmpty
                 ? "Tap the map to draw a damage zone polygon"
                 : "\(polygonPoints.count) point\(polygonPoints.count == 1 ? "" : "s") — tap to add more")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if !polygonPoints.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            _ = polygonPoints.popLast()
                        }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        withAnimation(.snappy(duration: 0.2)) {
                            polygonPoints.removeAll()
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }

                if let region = visibleRegion {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            polygonPoints.append(CoordinatePoint(coordinate: region.center))
                        }
                    } label: {
                        Label("Add at Center", systemImage: "mappin")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Area Info

    private var damageAreaInfo: some View {
        Group {
            if polygonPoints.count >= 3 {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Damage Zone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.4f Ha", damageAreaHa))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.orange)
                    }

                    Divider().frame(height: 30)

                    VStack(spacing: 4) {
                        Text("Block Area")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f Ha", paddock.areaHectares))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.blue)
                    }

                    Divider().frame(height: 30)

                    VStack(spacing: 4) {
                        Text("% of Block")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        let pct = paddock.areaHectares > 0 ? (damageAreaHa / paddock.areaHectares) * 100 : 0
                        Text(String(format: "%.1f%%", pct))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            }
        }
    }

    // MARK: - Damage Details

    private var damageDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Damage Details", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Date")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $damageDate, displayedComponents: .date)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Type of Damage")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(DamageType.allCases, id: \.self) { type in
                        let isSelected = damageType == type
                        Button {
                            damageType = type
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: type.icon)
                                    .font(.caption2)
                                Text(type.rawValue)
                                    .font(.caption.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? .orange.opacity(0.15) : Color(.tertiarySystemFill))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? .orange : .clear, lineWidth: 1.5)
                            )
                            .foregroundStyle(isSelected ? .orange : .primary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Damage Amount (%)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("20", text: $damagePercentText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Slider(value: Binding(
                        get: { damagePercent },
                        set: { damagePercentText = String(format: "%.0f", $0) }
                    ), in: 1...100, step: 5)
                    .tint(.orange)

                    Text("\(Int(damagePercent))%")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes (optional)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Additional details...", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            let record = DamageRecord(
                vineyardId: paddock.vineyardId,
                paddockId: paddock.id,
                polygonPoints: polygonPoints,
                date: damageDate,
                damageType: damageType,
                damagePercent: damagePercent,
                notes: notes
            )
            store.addDamageRecord(record)
            showConfirmation = true
        } label: {
            Label("Save Damage Record", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!isValid)
    }

    // MARK: - Helpers

    private func fitMapToPaddock() {
        let points = paddock.polygonPoints
        guard !points.isEmpty else { return }
        let minLat = points.map(\.latitude).min()!
        let maxLat = points.map(\.latitude).max()!
        let minLon = points.map(\.longitude).min()!
        let maxLon = points.map(\.longitude).max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.001,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.001
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct DamageMidpointEdge: Sendable {
    let id: String
    let midpoint: CLLocationCoordinate2D
    let insertIndex: Int
}

private struct DamagePointHandle: View {
    let index: Int
    let isDragging: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isDragging ? .red : .orange)
                .frame(width: isDragging ? 30 : 24, height: isDragging ? 30 : 24)
                .overlay {
                    Circle().stroke(.white, lineWidth: 2)
                }
                .shadow(color: isDragging ? .red.opacity(0.5) : .black.opacity(0.3), radius: isDragging ? 8 : 4)
            Text("\(index + 1)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .animation(.snappy(duration: 0.15), value: isDragging)
    }
}

private struct DamageMidpointHandle: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.2), radius: 3)
            Image(systemName: "plus")
                .font(.caption2.bold())
                .foregroundStyle(.orange)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
}
