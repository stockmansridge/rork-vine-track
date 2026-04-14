import SwiftUI
import CoreLocation

struct SprayRecordFormView: View {
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss) private var dismiss

    let tripId: UUID
    let paddockIds: [UUID]
    var existingRecord: SprayRecord?

    @State private var date: Date
    @State private var startTime: Date

    @State private var temperatureText: String
    @State private var windSpeedText: String
    @State private var windDirection: String
    @State private var humidityText: String
    @State private var tanks: [SprayTank]
    @State private var sprayReference: String
    @State private var notes: String
    @State private var numberOfFansJets: String
    @State private var averageSpeedText: String
    @State private var equipmentType: String
    @State private var tractor: String
    @State private var tractorGear: String
    @State private var expandedTankId: UUID?
    @State private var weatherDataService = WeatherDataService()



    private func chemicalBinding(tankIndex tIdx: Int, chemicalIndex cIdx: Int) -> Binding<SprayChemical> {
        Binding(
            get: { tanks[tIdx].chemicals[cIdx] },
            set: { newValue in tanks[tIdx].chemicals[cIdx] = newValue }
        )
    }

    init(tripId: UUID, paddockIds: [UUID], existingRecord: SprayRecord? = nil) {
        self.tripId = tripId
        self.paddockIds = paddockIds
        self.existingRecord = existingRecord

        let record = existingRecord
        _date = State(initialValue: record?.date ?? Date())
        _startTime = State(initialValue: record?.startTime ?? Date())

        _temperatureText = State(initialValue: record?.temperature.map { String(format: "%.1f", $0) } ?? "")
        _windSpeedText = State(initialValue: record?.windSpeed.map { String(format: "%.1f", $0) } ?? "")
        _windDirection = State(initialValue: record?.windDirection ?? "")
        _humidityText = State(initialValue: record?.humidity.map { String(format: "%.0f", $0) } ?? "")
        _sprayReference = State(initialValue: record?.sprayReference ?? "")
        _tanks = State(initialValue: record?.tanks ?? [SprayTank(tankNumber: 1)])
        _notes = State(initialValue: record?.notes ?? "")
        _numberOfFansJets = State(initialValue: record?.numberOfFansJets ?? "")
        _averageSpeedText = State(initialValue: record?.averageSpeed.map { String(format: "%.1f", $0) } ?? "")
        _equipmentType = State(initialValue: record?.equipmentType ?? "")
        _tractor = State(initialValue: record?.tractor ?? "")
        _tractorGear = State(initialValue: record?.tractorGear ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                sprayReferenceSection
                weatherSection
                tankCountSection

                ForEach(Array(tanks.enumerated()), id: \.element.id) { tIdx, _ in
                    tankSection(tIdx: tIdx)
                }

                chemicalTotalsSection
                equipmentSection
                notesSection
            }
            .navigationTitle(existingRecord != nil ? "Edit Spray Record" : "Spray Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecord() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }

        }
        .onAppear {
            if existingRecord == nil {
                applyDefaultsFromLastSpray()
                autoCalculateAverageSpeed()
            }
            if expandedTankId == nil, let firstTank = tanks.first {
                expandedTankId = firstTank.id
            }
        }
    }

    private func autoCalculateAverageSpeed() {
        guard averageSpeedText.isEmpty else { return }
        guard let trip = store.trips.first(where: { $0.id == tripId }),
              trip.totalDistance > 0,
              let endTime = trip.endTime else { return }
        let duration = endTime.timeIntervalSince(trip.startTime)
        guard duration > 0 else { return }
        let distanceKm = trip.totalDistance / 1000.0
        let hours = duration / 3600.0
        let speed = distanceKm / hours
        averageSpeedText = String(format: "%.1f", speed)
    }

    private func applyDefaultsFromLastSpray() {
        let lastRecord = store.sprayRecords
            .filter { $0.id != existingRecord?.id }
            .sorted { $0.date > $1.date }
            .first

        if let last = lastRecord {
            if equipmentType.isEmpty { equipmentType = last.equipmentType }
            if tractor.isEmpty { tractor = last.tractor }
            if tractorGear.isEmpty { tractorGear = last.tractorGear }
            if numberOfFansJets.isEmpty { numberOfFansJets = last.numberOfFansJets }

            if let lastTank = last.tanks.first {
                for i in tanks.indices {
                    if tanks[i].waterVolume == 0 {
                        tanks[i].waterVolume = lastTank.waterVolume
                    }
                    if tanks[i].sprayRatePerHa == 0 {
                        tanks[i].sprayRatePerHa = lastTank.sprayRatePerHa
                    }
                    if tanks[i].concentrationFactor == 0 && lastTank.concentrationFactor > 0 {
                        tanks[i].concentrationFactor = lastTank.concentrationFactor
                    }
                    if tanks[i].chemicals.isEmpty && !lastTank.chemicals.isEmpty {
                        tanks[i].chemicals = lastTank.chemicals.map { chem in
                            SprayChemical(name: chem.name, ratePerHa: chem.ratePerHa, costPerUnit: chem.costPerUnit)
                        }
                    }
                }
            }
        } else {
            applyDefaultsToTanks()
        }

        recalculateAllChemicalVolumes()
    }

    private func applyDefaultsToTanks() {
    }

    private func recalculateAllChemicalVolumes() {
        for tIdx in tanks.indices {
            for cIdx in tanks[tIdx].chemicals.indices {
                let recVol = recommendedVolPerTank(
                    waterVolume: tanks[tIdx].waterVolume,
                    ratePerHa: tanks[tIdx].chemicals[cIdx].ratePerHa,
                    sprayRatePerHa: tanks[tIdx].sprayRatePerHa,
                    concentrationFactor: tanks[tIdx].concentrationFactor
                )
                if recVol > 0 {
                    tanks[tIdx].chemicals[cIdx].volumePerTank = recVol
                }
            }
        }
    }

    private func applyPreset(_ preset: SavedSprayPreset, toTankIndex tIdx: Int) {
        tanks[tIdx].waterVolume = preset.waterVolume
        tanks[tIdx].sprayRatePerHa = preset.sprayRatePerHa
        tanks[tIdx].concentrationFactor = preset.concentrationFactor
    }

    private func applyChemicalPreset(_ saved: SavedChemical, toTankIndex tIdx: Int, chemicalIndex cIdx: Int) {
        tanks[tIdx].chemicals[cIdx].name = saved.name
        tanks[tIdx].chemicals[cIdx].ratePerHa = saved.ratePerHa
        if let purchase = saved.purchase, purchase.costPerBaseUnit > 0 {
            tanks[tIdx].chemicals[cIdx].costPerUnit = purchase.costPerBaseUnit
        }
        let recommendedVol = recommendedVolPerTank(
            waterVolume: tanks[tIdx].waterVolume,
            ratePerHa: saved.ratePerHa,
            sprayRatePerHa: tanks[tIdx].sprayRatePerHa,
            concentrationFactor: tanks[tIdx].concentrationFactor
        )
        tanks[tIdx].chemicals[cIdx].volumePerTank = recommendedVol
    }

    private func autoSaveChemical(name: String, ratePerHa: Double) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ratePerHa > 0 else { return }
        if store.savedChemicals.contains(where: { $0.name.lowercased() == trimmed.lowercased() && $0.ratePerHa == ratePerHa }) {
            return
        }
        if let existing = store.savedChemicals.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            var updated = existing
            updated.ratePerHa = ratePerHa
            store.updateSavedChemical(updated)
        } else {
            store.addSavedChemical(SavedChemical(name: trimmed, ratePerHa: ratePerHa))
        }
    }

    private func recommendedVolPerTank(waterVolume: Double, ratePerHa: Double, sprayRatePerHa: Double, concentrationFactor: Double = 0) -> Double {
        guard ratePerHa > 0, sprayRatePerHa > 0 else { return 0 }
        let effectiveCF = concentrationFactor > 0 ? concentrationFactor : 1.0
        let areaPerTank = (waterVolume * effectiveCF) / sprayRatePerHa
        return ratePerHa * areaPerTank
    }

    // MARK: - Weather Section

    private var sprayReferenceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label("Spray Ref", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Spray Number/Reference", text: $sprayReference)
                    .font(.body)
            }
        } header: {
            Text("Spray Reference")
        }
    }

    private var weatherSection: some View {
        Section {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)

            LabeledContent {
                TextField("°C", text: $temperatureText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Temperature", systemImage: "thermometer")
            }

            LabeledContent {
                TextField("km/h", text: $windSpeedText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Wind Speed", systemImage: "wind")
            }

            Picker("Wind Direction", selection: $windDirection) {
                Text("Select").tag("")
                ForEach(WindDirection.allCases, id: \.rawValue) { dir in
                    Text(dir.rawValue).tag(dir.rawValue)
                }
            }

            LabeledContent {
                TextField("%", text: $humidityText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Humidity", systemImage: "humidity")
            }

            fetchWeatherButton

            if let error = weatherDataService.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let obs = weatherDataService.lastObservation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VineyardTheme.leafGreen)
                    Text("Data from **\(obs.stationID)**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Weather Conditions")
        }
    }

    private var fetchWeatherButton: some View {
        Button {
            Task {
                let fallbackLocation = vineyardCentroidLocation
                await weatherDataService.fetchForStationOrNearest(
                    stationId: store.settings.weatherStationId,
                    location: locationService.location ?? fallbackLocation
                )
                if let obs = weatherDataService.lastObservation {
                    if let temp = obs.temperature {
                        temperatureText = String(format: "%.1f", temp)
                    }
                    if let wind = obs.windSpeed {
                        windSpeedText = String(format: "%.1f", wind)
                    }
                    if let dir = obs.windDirection {
                        windDirection = dir
                    }
                    if let hum = obs.humidity {
                        humidityText = String(format: "%.0f", hum)
                    }
                }
            }
        } label: {
            HStack {
                Label("Fetch Current Weather", systemImage: "arrow.down.circle")
                Spacer()
                if weatherDataService.isLoading {
                    ProgressView()
                }
            }
        }
        .disabled(weatherDataService.isLoading)
    }

    private var vineyardCentroidLocation: CLLocation? {
        let relevantPaddocks = store.paddocks.filter { paddockIds.contains($0.id) }
        let allPoints = relevantPaddocks.flatMap { $0.polygonPoints }
        guard !allPoints.isEmpty else {
            let allPaddockPoints = store.paddocks.flatMap { $0.polygonPoints }
            guard !allPaddockPoints.isEmpty else { return nil }
            let lat = allPaddockPoints.map(\.latitude).reduce(0, +) / Double(allPaddockPoints.count)
            let lon = allPaddockPoints.map(\.longitude).reduce(0, +) / Double(allPaddockPoints.count)
            return CLLocation(latitude: lat, longitude: lon)
        }
        let lat = allPoints.map(\.latitude).reduce(0, +) / Double(allPoints.count)
        let lon = allPoints.map(\.longitude).reduce(0, +) / Double(allPoints.count)
        return CLLocation(latitude: lat, longitude: lon)
    }

    // MARK: - Tank Count

    private var tankCountSection: some View {
        Section {
            Stepper("Number of Tanks: \(tanks.count)", value: Binding(
                get: { tanks.count },
                set: { newCount in
                    if newCount > tanks.count {
                        let defaultPreset = store.savedSprayPresets.first
                        for i in tanks.count..<newCount {
                            tanks.append(SprayTank(
                                tankNumber: i + 1
                            ))
                        }
                    } else if newCount < tanks.count && newCount >= 1 {
                        tanks = Array(tanks.prefix(newCount))
                    }
                }
            ), in: 1...20)
        } header: {
            Text("Tanks")
        }
    }

    // MARK: - Tank Section

    private func tankSection(tIdx: Int) -> some View {
        let tank = tanks[tIdx]
        let isExpanded = expandedTankId == tank.id
        return Section {
            Button {
                withAnimation(.snappy) {
                    expandedTankId = isExpanded ? nil : tank.id
                }
            } label: {
                HStack {
                    Label("Tank \(tank.tankNumber)", systemImage: "drop.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if tank.areaPerTank > 0 {
                        Text(String(format: "%.2f Ha/tank", tank.areaPerTank))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                tankPresetPicker(tIdx: tIdx)
                tankDetailFields(tIdx: tIdx)
                tankChemicals(tIdx: tIdx)
            }
        }
    }

    @ViewBuilder
    private func tankPresetPicker(tIdx: Int) -> some View {
        if !store.savedSprayPresets.isEmpty {
            Menu {
                ForEach(store.savedSprayPresets) { preset in
                    Button {
                        applyPreset(preset, toTankIndex: tIdx)
                    } label: {
                        VStack {
                            Text(preset.name)
                            Text("\(Int(preset.waterVolume))L • \(Int(preset.sprayRatePerHa))L/Ha • CF \(String(format: "%.1f", preset.concentrationFactor))")
                        }
                    }
                }
            } label: {
                HStack {
                    Label("Load Preset", systemImage: "tray.and.arrow.down")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func doubleStringBinding(_ keyPath: WritableKeyPath<SprayTank, Double>, tIdx: Int, blankValue: Double = 0) -> Binding<String> {
        Binding<String>(
            get: {
                let val = tanks[tIdx][keyPath: keyPath]
                if val == blankValue { return "" }
                if val == val.rounded() { return String(format: "%.0f", val) }
                return String(format: "%g", val)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    tanks[tIdx][keyPath: keyPath] = blankValue
                } else if let parsed = Double(trimmed) {
                    tanks[tIdx][keyPath: keyPath] = parsed
                }
                recalculateAllChemicalVolumes()
            }
        )
    }

    @ViewBuilder
    private func tankDetailFields(tIdx: Int) -> some View {
        LabeledContent {
            TextField("1500", text: doubleStringBinding(\.waterVolume, tIdx: tIdx))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        } label: {
            Text("Water Volume (L)")
                .font(.subheadline)
        }

        LabeledContent {
            TextField("750", text: doubleStringBinding(\.sprayRatePerHa, tIdx: tIdx))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        } label: {
            Text("Spray Rate (L/Ha)")
                .font(.subheadline)
        }

        LabeledContent {
            TextField("1.0", text: doubleStringBinding(\.concentrationFactor, tIdx: tIdx, blankValue: 0))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        } label: {
            Text("Concentration Factor")
                .font(.subheadline)
        }

        if tanks[tIdx].areaPerTank > 0 {
            HStack {
                Text("Area per Tank")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f Ha", tanks[tIdx].areaPerTank))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .listRowBackground(Color.accentColor.opacity(0.06))
        }
    }

    // MARK: - Chemicals

    @ViewBuilder
    private func tankChemicals(tIdx: Int) -> some View {
        HStack {
            Text("Chemicals")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                tanks[tIdx].chemicals.append(SprayChemical())
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }

        ForEach(tanks[tIdx].chemicals.indices, id: \.self) { cIdx in
            let chemBinding = chemicalBinding(tankIndex: tIdx, chemicalIndex: cIdx)
            let chemical = tanks[tIdx].chemicals[cIdx]
            let chemId = chemical.id
            VStack(spacing: 10) {
                HStack {
                    Menu {
                        if !store.savedChemicals.isEmpty {
                            ForEach(store.savedChemicals) { saved in
                                Button {
                                    applyChemicalPreset(saved, toTankIndex: tIdx, chemicalIndex: cIdx)
                                } label: {
                                    Text("\(saved.name) — \(String(format: "%.2f", saved.ratePerHa)) L/Kg/Ha")
                                }
                            }
                            Divider()
                        }
                        Button {
                        } label: {
                            Label("Type custom name below", systemImage: "pencil")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flask.fill")
                                .font(.caption)
                                .foregroundStyle(VineyardTheme.olive)
                            Text(chemical.name.isEmpty ? "Select Chemical" : chemical.name)
                                .font(.subheadline)
                                .foregroundStyle(chemical.name.isEmpty ? .secondary : .primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        tanks[tIdx].chemicals.removeAll { $0.id == chemId }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }

                TextField("Or type chemical name", text: chemBinding.name)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rate/Ha (L/Kg)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("0", value: chemBinding.ratePerHa, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.subheadline)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vol/Tank (L/Kg)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("0", value: chemBinding.volumePerTank, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.subheadline)
                    }
                }

                let recVol = recommendedVolPerTank(
                    waterVolume: tanks[tIdx].waterVolume,
                    ratePerHa: tanks[tIdx].chemicals[cIdx].ratePerHa,
                    sprayRatePerHa: tanks[tIdx].sprayRatePerHa,
                    concentrationFactor: tanks[tIdx].concentrationFactor
                )
                HStack(spacing: 6) {
                    Image(systemName: "function")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Rec. Vol/Tank")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if recVol > 0 {
                        Text(String(format: "%.2f L/Kg", recVol))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        if tanks[tIdx].chemicals[cIdx].volumePerTank != recVol {
                            Button {
                                tanks[tIdx].chemicals[cIdx].volumePerTank = recVol
                            } label: {
                                Text("Apply")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(.capsule)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Text("Enter rate & water vol")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.06))
                .clipShape(.rect(cornerRadius: 8))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Chemical Totals

    private var chemicalTotalsSection: some View {
        let allChemicals = tanks.flatMap { $0.chemicals }
        let grouped = Dictionary(grouping: allChemicals, by: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let totals = grouped.compactMap { (key, chems) -> (String, Double, ChemicalUnit)? in
            guard !key.isEmpty else { return nil }
            let displayName = chems.first?.name ?? key
            let unit = chems.first?.unit ?? .litres
            let totalBase = chems.reduce(0.0) { $0 + $1.volumePerTank }
            return (displayName, totalBase, unit)
        }.sorted { $0.0.lowercased() < $1.0.lowercased() }

        return Group {
            if !totals.isEmpty {
                Section {
                    ForEach(totals, id: \.0) { name, totalBase, unit in
                        let displayTotal = unit.fromBase(totalBase)
                        let unitAbbrev = unit == .litres ? "L" : unit == .kilograms ? "Kg" : unit.rawValue
                        HStack {
                            Label(name, systemImage: "flask.fill")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2f%@", displayTotal, unitAbbrev))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } header: {
                    Text("Chemical Totals (All Tanks)")
                }
            }
        }
    }

    // MARK: - Equipment

    private var equipmentSection: some View {
        Section {
            equipmentOptionField(
                label: "Equipment Type",
                icon: "wrench.and.screwdriver",
                text: $equipmentType,
                category: SavedEquipmentOption.categoryEquipmentType
            )
            equipmentOptionField(
                label: "Tractor",
                icon: "steeringwheel",
                text: $tractor,
                category: SavedEquipmentOption.categoryTractor
            )
            equipmentOptionField(
                label: "Tractor Gear",
                icon: "gearshape",
                text: $tractorGear,
                category: SavedEquipmentOption.categoryTractorGear
            )
            LabeledContent {
                TextField("Count", text: $numberOfFansJets)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("No. Fans/Jets", systemImage: "wind")
            }
        } header: {
            Text("Equipment")
        }
    }

    private func equipmentOptionField(label: String, icon: String, text: Binding<String>, category: String) -> some View {
        let savedOptions = store.equipmentOptions(for: category)
        return LabeledContent {
            HStack(spacing: 6) {
                TextField("Enter or select", text: text)
                    .multilineTextAlignment(.trailing)
                if !savedOptions.isEmpty {
                    Menu {
                        ForEach(savedOptions) { option in
                            Button(option.value) {
                                text.wrappedValue = option.value
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            Label(label, systemImage: icon)
        }
    }

    private func autoSaveEquipmentOptions() {
        let entries: [(String, String)] = [
            (SavedEquipmentOption.categoryEquipmentType, equipmentType),
            (SavedEquipmentOption.categoryTractor, tractor),
            (SavedEquipmentOption.categoryTractorGear, tractorGear)
        ]
        for (category, value) in entries {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            store.addEquipmentOption(SavedEquipmentOption(category: category, value: trimmed))
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes") {
            TextField("Additional notes...", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Save

    private func saveRecord() {
        for tank in tanks {
            for chemical in tank.chemicals {
                autoSaveChemical(name: chemical.name, ratePerHa: chemical.ratePerHa)
            }
        }

        autoSaveEquipmentOptions()

        let record = SprayRecord(
            id: existingRecord?.id ?? UUID(),
            tripId: tripId,
            vineyardId: store.selectedVineyardId ?? UUID(),
            date: date,
            startTime: startTime,
            endTime: existingRecord?.endTime,
            temperature: Double(temperatureText),
            windSpeed: Double(windSpeedText),
            windDirection: windDirection,
            humidity: Double(humidityText),
            sprayReference: sprayReference,
            tanks: tanks,
            notes: notes,
            numberOfFansJets: numberOfFansJets,
            averageSpeed: Double(averageSpeedText),
            equipmentType: equipmentType,
            tractor: tractor,
            tractorGear: tractorGear
        )

        if existingRecord != nil {
            store.updateSprayRecord(record)
        } else {
            store.addSprayRecord(record)
        }

        if var trip = store.trips.first(where: { $0.id == tripId }), trip.isActive {
            trip.totalTanks = tanks.count
            store.updateTrip(trip)
        }

        dismiss()
    }
}

struct SavedChemicalPickerSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSelect: (SavedChemical) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.savedChemicals) { chemical in
                    Button {
                        onSelect(chemical)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chemical.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Rate: \(String(format: "%.2f", chemical.ratePerHa)) L/Kg per Ha")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Saved Chemicals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if store.savedChemicals.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Chemicals", systemImage: "flask")
                    } description: {
                        Text("Add chemicals in Settings → Spray Presets to quickly select them here.")
                    }
                }
            }
        }
    }
}
