import SwiftUI
import MapKit

struct EditPaddockSheet: View {
    let paddock: Paddock?
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var polygonPoints: [CoordinatePoint] = []
    @State private var rowDirection: Double = 0
    @State private var rowCount: Int = 0
    @State private var rowWidth: Double = 2.5
    @State private var rowOffset: Double = 0
    @State private var rowStartNumber: Int = 1
    @State private var rowNumberAscending: Bool = true
    @State private var vineSpacing: Double = 1.0
    @State private var vineCountOverride: String = ""
    @State private var rowLengthOverride: String = ""
    @State private var flowPerEmitterText: String = ""
    @State private var emitterSpacingText: String = ""
    @State private var showBoundaryEditor: Bool = false
    @State private var showFullscreenRowConfig: Bool = false

    private var isEditing: Bool { paddock != nil }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                boundarySection
                rowConfigSection
                if rowCount > 0 {
                    rowNumberingSection
                }
                vineSpacingSection
                irrigationSection
                if polygonPoints.count > 2 && rowCount > 0 {
                    blockSummarySection
                }
            }
            .navigationTitle(isEditing ? "Edit Block" : "New Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePaddock()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .fullScreenCover(isPresented: $showBoundaryEditor) {
                BoundaryMapEditor(
                    polygonPoints: $polygonPoints,
                    existingPaddocks: store.paddocks.filter { $0.id != paddock?.id && $0.polygonPoints.count > 2 }
                )
            }
            .fullScreenCover(isPresented: $showFullscreenRowConfig) {
                RowConfigMapOverlay(
                    rowDirection: $rowDirection,
                    rowCount: $rowCount,
                    rowWidth: $rowWidth,
                    rowOffset: $rowOffset,
                    rowStartNumber: $rowStartNumber,
                    rowNumberAscending: $rowNumberAscending,
                    polygonPoints: polygonPoints
                )
            }
            .onAppear {
                if let paddock {
                    name = paddock.name
                    polygonPoints = paddock.polygonPoints
                    rowDirection = paddock.rowDirection
                    rowCount = paddock.rows.count
                    rowWidth = paddock.rowWidth
                    rowOffset = paddock.rowOffset
                    vineSpacing = paddock.vineSpacing
                    if let override = paddock.vineCountOverride {
                        vineCountOverride = "\(override)"
                    }
                    if let rlOverride = paddock.rowLengthOverride {
                        rowLengthOverride = String(format: "%.0f", rlOverride)
                    }
                    if let flow = paddock.flowPerEmitter {
                        flowPerEmitterText = String(format: "%.1f", flow)
                    }
                    if let spacing = paddock.emitterSpacing {
                        emitterSpacingText = String(format: "%.2f", spacing)
                    }
                    if let firstRow = paddock.rows.first, let lastRow = paddock.rows.last {
                        rowNumberAscending = lastRow.number >= firstRow.number
                        rowStartNumber = min(firstRow.number, lastRow.number)
                    }
                }
            }
        }
    }

    private var nameSection: some View {
        Section("Block Name") {
            TextField("e.g. Block A", text: $name)
        }
    }

    private var boundarySection: some View {
        Section {
            Button {
                showBoundaryEditor = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Edit Boundary", systemImage: "pentagon")
                            .font(.body)
                        if polygonPoints.isEmpty {
                            Text("Tap to draw boundary on map")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(polygonPoints.count) boundary points set")
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

            if !polygonPoints.isEmpty {
                Button("Clear Boundary", role: .destructive) {
                    polygonPoints.removeAll()
                }
                .font(.subheadline)
            }
        } header: {
            Text("Boundary")
        }
    }

    private var computedFirstRowNumber: Int {
        rowNumberAscending ? rowStartNumber : rowStartNumber + max(rowCount - 1, 0)
    }

    private var computedLastRowNumber: Int {
        rowNumberAscending ? rowStartNumber + max(rowCount - 1, 0) : rowStartNumber
    }

    private var rowConfigSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Direction")
                        .font(.subheadline)
                    Spacer()
                    Text("\(String(format: "%.1f", rowDirection))\u{00B0}")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.blue)
                }
                HStack(spacing: 12) {
                    Button {
                        rowDirection = max(0, rowDirection - 0.5)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Slider(value: $rowDirection, in: 0...360, step: 0.5)

                    Button {
                        rowDirection = min(360, rowDirection + 0.5)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Stepper("Number of Rows: \(rowCount)", value: $rowCount, in: 0...500)

            VStack(alignment: .leading, spacing: 4) {
                Text("Row Width: \(rowWidth, specifier: "%.1f") m")
                    .font(.subheadline)
                Slider(value: $rowWidth, in: 0.0...4.0, step: 0.1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Shift Rows: \(rowOffset, specifier: "%.1f") m")
                        .font(.subheadline)
                    Spacer()
                    Button("Reset") { rowOffset = 0 }
                        .font(.caption)
                        .disabled(rowOffset == 0)
                }
                HStack(spacing: 12) {
                    Button {
                        rowOffset -= 0.5
                    } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Slider(value: $rowOffset, in: -50...50, step: 0.25)

                    Button {
                        rowOffset += 0.5
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if polygonPoints.count > 2 {
                ZStack(alignment: .topTrailing) {
                    RowPreviewMapView(
                        polygonPoints: polygonPoints,
                        rowDirection: rowDirection,
                        rowCount: rowCount,
                        rowWidth: rowWidth,
                        rowOffset: rowOffset,
                        firstRowNumber: computedFirstRowNumber,
                        lastRowNumber: computedLastRowNumber,
                        showRowLabels: rowCount > 0
                    )
                    .frame(height: 300)
                    .clipShape(.rect(cornerRadius: 10))

                    Button {
                        showFullscreenRowConfig = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(8)
                }
            }
        } header: {
            Text("Row Configuration")
        } footer: {
            if polygonPoints.count > 2 && rowCount > 0 {
                Text("Green lines show row positions. Tap expand to configure on fullscreen map.")
            } else if polygonPoints.count < 3 {
                Text("Set a boundary first to preview rows on the map.")
            } else {
                Text("Set the compass direction, total number, and width of the rows.")
            }
        }
    }

    private var rowNumberingSection: some View {
        Section {
            Stepper("Start at: \(rowStartNumber)", value: $rowStartNumber, in: 1...9999)

            Picker("Row 1 Position", selection: $rowNumberAscending) {
                Label("Row \(rowStartNumber) on Left", systemImage: "arrow.right").tag(true)
                Label("Row \(rowStartNumber) on Right", systemImage: "arrow.left").tag(false)
            }
        } header: {
            Text("Row Numbering")
        } footer: {
            let lastNum: Int = rowStartNumber + max(rowCount - 1, 0)
            if rowNumberAscending {
                Text("Row \(rowStartNumber) (left) → Row \(lastNum) (right)")
            } else {
                Text("Row \(lastNum) (left) → Row \(rowStartNumber) (right)")
            }
        }
    }

    private var irrigationFlowPerEmitter: Double? {
        guard let val = Double(flowPerEmitterText), val > 0 else { return nil }
        return val
    }

    private var irrigationEmitterSpacing: Double? {
        guard let val = Double(emitterSpacingText), val > 0 else { return nil }
        return val
    }

    private var irrigationSection: some View {
        Section {
            HStack {
                Text("Flow per Emitter")
                    .font(.subheadline)
                Spacer()
                TextField("0.0", text: $flowPerEmitterText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Text("L/hr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Emitter Spacing")
                    .font(.subheadline)
                Spacer()
                TextField("0.00", text: $emitterSpacingText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Text("m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let flow = irrigationFlowPerEmitter, let spacing = irrigationEmitterSpacing, rowWidth > 0 {
                let emittersPerHa = 10_000.0 / (rowWidth * spacing)
                let litresPerHaHr = emittersPerHa * flow
                let mlPerHaHr = litresPerHaHr / 1_000_000.0
                let mmHr = mlPerHaHr * 100.0

                Divider()

                HStack {
                    Label("ML/ha/hr", systemImage: "drop.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(String(format: "%.4f", mlPerHaHr))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.blue)
                }

                HStack {
                    Label("mm/hr", systemImage: "ruler")
                        .font(.subheadline)
                        .foregroundStyle(.teal)
                    Spacer()
                    Text(String(format: "%.2f", mmHr))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "drop.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text("Irrigation")
            }
        } footer: {
            Text("ML/ha/hr = (emitters per ha × flow) ÷ 1,000,000. mm/hr = ML/ha/hr × 100. Row spacing (\(String(format: "%.1f", rowWidth)) m) is used for the calculation.")
        }
    }

    private var vineSpacingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vine Spacing: \(vineSpacing, specifier: "%.2f") m")
                    .font(.subheadline)
                Slider(value: $vineSpacing, in: 0.5...3.0, step: 0.05)
            }
        } header: {
            Text("Vine Spacing")
        } footer: {
            Text("Distance between each vine along a row. Used to estimate total vine count.")
        }
    }

    private var blockSummarySection: some View {
        let polygonCoords = polygonPoints.map { $0.coordinate }
        let lines = calculateRowLines(
            polygonCoords: polygonCoords,
            direction: rowDirection,
            count: max(rowCount, 0),
            width: rowWidth,
            offset: rowOffset
        )
        let mPerDegLat = 111_320.0
        let centroidLat = polygonPoints.isEmpty ? 0 : polygonPoints.map(\.latitude).reduce(0, +) / Double(polygonPoints.count)
        let mPerDegLon = 111_320.0 * cos(centroidLat * .pi / 180.0)
        let totalLength = lines.reduce(0.0) { total, line in
            let dLat = (line.end.latitude - line.start.latitude) * mPerDegLat
            let dLon = (line.end.longitude - line.start.longitude) * mPerDegLon
            return total + sqrt(dLat * dLat + dLon * dLon)
        }
        let effectiveRowLength = Double(rowLengthOverride) ?? totalLength
        let estimatedVines = vineSpacing > 0 ? Int(effectiveRowLength / vineSpacing) : 0
        let displayVines = Int(vineCountOverride) ?? estimatedVines

        return Section {
            HStack {
                Text("Calculated Row Length")
                    .font(.subheadline)
                Spacer()
                Text("\(String(format: "%.0f", totalLength)) m")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Estimated Vines")
                    .font(.subheadline)
                Spacer()
                Text("\(estimatedVines)")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Calculation Overrides")
                    .font(.subheadline.weight(.semibold))

                Label("Used for water usage & yield estimates only — does not affect trip path tracking.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Row Length")
                        .font(.subheadline)
                    Spacer()
                    TextField("\(String(format: "%.0f", totalLength))", text: $rowLengthOverride)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    Text("m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Vine Count")
                        .font(.subheadline)
                    Spacer()
                    TextField("\(estimatedVines)", text: $vineCountOverride)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                }

                if !rowLengthOverride.isEmpty || !vineCountOverride.isEmpty {
                    HStack {
                        Label("Manual override active", systemImage: "pencil.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Reset All") {
                            rowLengthOverride = ""
                            vineCountOverride = ""
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text("Block Summary")
            }
        } footer: {
            Text("Row length and vine count are auto-calculated from boundary geometry. Override values here for more accurate water usage and yield calculations — trip path tracking always uses the mapped row geometry.")
        }
    }

    private func savePaddock() {
        let polygonCoords = polygonPoints.map { $0.coordinate }
        let lines = calculateRowLines(
            polygonCoords: polygonCoords,
            direction: rowDirection,
            count: max(rowCount, 0),
            width: rowWidth,
            offset: rowOffset
        )

        let rows: [PaddockRow] = (0..<max(rowCount, 0)).map { index in
            let number: Int = rowNumberAscending ? rowStartNumber + index : rowStartNumber + (rowCount - 1 - index)
            let startCoord: CoordinatePoint
            let endCoord: CoordinatePoint
            if index < lines.count {
                startCoord = CoordinatePoint(coordinate: lines[index].start)
                endCoord = CoordinatePoint(coordinate: lines[index].end)
            } else {
                startCoord = CoordinatePoint(latitude: 0, longitude: 0)
                endCoord = CoordinatePoint(latitude: 0, longitude: 0)
            }
            return PaddockRow(
                number: number,
                startPoint: startCoord,
                endPoint: endCoord
            )
        }

        if var existing = paddock {
            existing.name = name
            existing.polygonPoints = polygonPoints
            existing.rowDirection = rowDirection
            existing.rows = rows
            existing.rowWidth = rowWidth
            existing.rowOffset = rowOffset
            existing.vineSpacing = vineSpacing
            existing.vineCountOverride = Int(vineCountOverride)
            existing.rowLengthOverride = Double(rowLengthOverride)
            existing.flowPerEmitter = irrigationFlowPerEmitter
            existing.emitterSpacing = irrigationEmitterSpacing
            store.updatePaddock(existing)
        } else {
            let newPaddock = Paddock(
                name: name,
                polygonPoints: polygonPoints,
                rows: rows,
                rowDirection: rowDirection,
                rowWidth: rowWidth,
                rowOffset: rowOffset,
                vineSpacing: vineSpacing,
                vineCountOverride: Int(vineCountOverride),
                rowLengthOverride: Double(rowLengthOverride),
                flowPerEmitter: irrigationFlowPerEmitter,
                emitterSpacing: irrigationEmitterSpacing
            )
            store.addPaddock(newPaddock)
        }
    }
}
