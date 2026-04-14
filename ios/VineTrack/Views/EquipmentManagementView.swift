import SwiftUI

struct EquipmentManagementView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.accessControl) private var accessControl
    @State private var showAddSheet: Bool = false
    @State private var editingEquipment: SprayEquipmentItem?
    @State private var showAddTractorSheet: Bool = false
    @State private var editingTractor: Tractor?
    @State private var showAddFuelSheet: Bool = false
    @State private var editingFuelPurchase: FuelPurchase?

    var body: some View {
        List {
            Section {
                ForEach(store.sprayEquipment) { item in
                    Button {
                        editingEquipment = item
                    } label: {
                        EquipmentRow(equipment: item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if accessControl?.canDelete ?? true {
                            Button(role: .destructive) {
                                store.deleteSprayEquipment(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Label("Spray Rigs & Tanks", systemImage: "wrench.and.screwdriver")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Spacer()
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                }
            }

            Section {
                ForEach(store.tractors) { tractor in
                    Button {
                        editingTractor = tractor
                    } label: {
                        TractorRow(tractor: tractor)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if accessControl?.canDelete ?? true {
                            Button(role: .destructive) {
                                store.deleteTractor(tractor)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Label("Tractors", systemImage: "truck.pickup.side.fill")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Spacer()
                    Button {
                        showAddTractorSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                }
            } footer: {
                Text("Fuel usage (L/hr) can typically be found in your tractor's user manual under the engine specifications section.")
            }

            Section {
                ForEach(store.fuelPurchases.sorted(by: { $0.date > $1.date })) { purchase in
                    Button {
                        editingFuelPurchase = purchase
                    } label: {
                        FuelPurchaseRow(purchase: purchase)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if accessControl?.canDelete ?? true {
                            Button(role: .destructive) {
                                store.deleteFuelPurchase(purchase)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                if !store.fuelPurchases.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Season Average")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("$\(String(format: "%.2f", store.seasonFuelCostPerLitre))/L")
                                .font(.headline.bold())
                                .foregroundStyle(VineyardTheme.olive)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Total Purchased")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let totalVol = store.fuelPurchases.reduce(0) { $0 + $1.volumeLitres }
                            Text("\(String(format: "%.0f", totalVol)) L")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Label("Plant Fuel Purchases", systemImage: "fuelpump.circle.fill")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Spacer()
                    Button {
                        showAddFuelSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                }
            } footer: {
                Text("Record fuel purchases to calculate an average cost per litre for the season. This is used in spray job costings.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.sprayEquipment.isEmpty && store.tractors.isEmpty && store.fuelPurchases.isEmpty {
                ContentUnavailableView {
                    Label("No Equipment", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Add your spray rigs, tanks, and tractors")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            EquipmentFormSheet(equipment: nil)
        }
        .sheet(item: $editingEquipment) { item in
            EquipmentFormSheet(equipment: item)
        }
        .sheet(isPresented: $showAddTractorSheet) {
            TractorFormSheet(tractor: nil)
        }
        .sheet(item: $editingTractor) { item in
            TractorFormSheet(tractor: item)
        }
        .sheet(isPresented: $showAddFuelSheet) {
            FuelPurchaseFormSheet(purchase: nil)
        }
        .sheet(item: $editingFuelPurchase) { item in
            FuelPurchaseFormSheet(purchase: item)
        }
    }
}

struct EquipmentRow: View {
    let equipment: SprayEquipmentItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(equipment.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Label("\(String(format: "%.0f", equipment.tankCapacityLitres)) L tank", systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct TractorRow: View {
    let tractor: Tractor

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tractor.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if !tractor.brand.isEmpty || !tractor.model.isEmpty {
                    HStack(spacing: 4) {
                        if !tractor.brand.isEmpty {
                            Text(tractor.brand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !tractor.brand.isEmpty && !tractor.model.isEmpty {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if !tractor.model.isEmpty {
                            Text(tractor.model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Label("\(String(format: "%.1f", tractor.fuelUsageLPerHour)) L/hr fuel usage", systemImage: "fuelpump.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct FuelPurchaseRow: View {
    let purchase: FuelPurchase

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(format: "%.0f", purchase.volumeLitres)) L — $\(String(format: "%.2f", purchase.totalCost))")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Label(purchase.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("$\(String(format: "%.2f", purchase.costPerLitre))/L")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VineyardTheme.olive)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct EquipmentFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store

    let equipment: SprayEquipmentItem?

    @State private var name: String = ""
    @State private var tankCapacity: String = ""

    init(equipment: SprayEquipmentItem?) {
        self.equipment = equipment
        if let e = equipment {
            _name = State(initialValue: e.name)
            _tankCapacity = State(initialValue: String(format: "%.0f", e.tankCapacityLitres))
        }
    }

    private var isValid: Bool {
        !name.isEmpty && (Double(tankCapacity) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Equipment Name", text: $name)
                } header: {
                    Text("Equipment Name")
                } footer: {
                    Text("A descriptive name for this spray rig or tank, e.g. \"200L Silvan UTE Sprayer\" or \"1500L Croplands QM-420\".")
                }

                Section {
                    TextField("e.g. 400", text: $tankCapacity)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Tank Capacity (litres)")
                } footer: {
                    Text("The total liquid capacity of the spray tank in litres. This is used to calculate how many tank loads are needed and the chemical amounts per tank.")
                }
            }
            .navigationTitle(equipment == nil ? "New Equipment" : "Edit Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let capacity = Double(tankCapacity) ?? 0
        if var existing = equipment {
            existing.name = name
            existing.tankCapacityLitres = capacity
            store.updateSprayEquipment(existing)
        } else {
            let newEquipment = SprayEquipmentItem(name: name, tankCapacityLitres: capacity)
            store.addSprayEquipment(newEquipment)
        }
    }
}

struct TractorFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store

    let tractor: Tractor?

    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var fuelUsage: String = ""
    @State private var isLookingUp: Bool = false
    @State private var lookupError: String?

    init(tractor: Tractor?) {
        self.tractor = tractor
        if let t = tractor {
            _brand = State(initialValue: t.brand)
            _model = State(initialValue: t.model)
            _fuelUsage = State(initialValue: String(format: "%.1f", t.fuelUsageLPerHour))
        }
    }

    private var isValid: Bool {
        !brand.isEmpty && !model.isEmpty && (Double(fuelUsage) ?? 0) > 0
    }

    private var canLookup: Bool {
        !brand.trimmingCharacters(in: .whitespaces).isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. John Deere", text: $brand)
                        .textContentType(.organizationName)
                    TextField("e.g. 5075E", text: $model)
                } header: {
                    Text("Tractor")
                } footer: {
                    Text("Enter the brand and model of your tractor. This is used to identify the tractor and look up fuel usage.")
                }

                Section {
                    HStack {
                        TextField("e.g. 8.5", text: $fuelUsage)
                            .keyboardType(.decimalPad)
                        Spacer()
                        Button {
                            lookupFuelUsage()
                        } label: {
                            if isLookingUp {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(VineyardTheme.olive)
                            }
                        }
                        .disabled(!canLookup || isLookingUp)
                    }
                } header: {
                    Text("Fuel Usage (L/hr)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The fuel consumption rate in litres per hour under working load (not idle). This is often found in the user manual under engine specifications or performance data.")
                        if canLookup {
                            Text("Tap the \(Image(systemName: "sparkles")) button to look up an estimated fuel usage for your \(brand) \(model).")
                                .foregroundStyle(VineyardTheme.olive)
                        }
                        if let lookupError {
                            Text(lookupError)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(tractor == nil ? "New Tractor" : "Edit Tractor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func lookupFuelUsage() {
        isLookingUp = true
        lookupError = nil
        Task {
            let result = await TractorFuelLookupService.shared.lookupFuelUsage(brand: brand.trimmingCharacters(in: .whitespaces), model: model.trimmingCharacters(in: .whitespaces))
            isLookingUp = false
            if let value = result {
                fuelUsage = String(format: "%.1f", value)
            } else {
                lookupError = "Could not find fuel usage data. Please enter manually."
            }
        }
    }

    private func save() {
        let usage = Double(fuelUsage) ?? 0
        let displayName = "\(brand) \(model)".trimmingCharacters(in: .whitespaces)
        if var existing = tractor {
            existing.brand = brand
            existing.model = model
            existing.name = displayName
            existing.fuelUsageLPerHour = usage
            store.updateTractor(existing)
        } else {
            let newTractor = Tractor(name: displayName, brand: brand, model: model, fuelUsageLPerHour: usage)
            store.addTractor(newTractor)
        }
    }
}

struct FuelPurchaseFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store

    let purchase: FuelPurchase?

    @State private var volumeText: String = ""
    @State private var costText: String = ""
    @State private var date: Date = Date()

    init(purchase: FuelPurchase?) {
        self.purchase = purchase
        if let p = purchase {
            _volumeText = State(initialValue: String(format: "%.0f", p.volumeLitres))
            _costText = State(initialValue: String(format: "%.2f", p.totalCost))
            _date = State(initialValue: p.date)
        }
    }

    private var isValid: Bool {
        (Double(volumeText) ?? 0) > 0 && (Double(costText) ?? 0) > 0
    }

    private var previewCostPerLitre: Double {
        let vol = Double(volumeText) ?? 0
        let cost = Double(costText) ?? 0
        guard vol > 0 else { return 0 }
        return cost / vol
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. 500", text: $volumeText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Volume (Litres)")
                } footer: {
                    Text("The total litres of fuel purchased.")
                }

                Section {
                    TextField("e.g. 950.00", text: $costText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Total Cost ($)")
                }

                Section {
                    DatePicker("Purchase Date", selection: $date, displayedComponents: .date)
                }

                if isValid {
                    Section {
                        HStack {
                            Text("Cost per Litre")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$\(String(format: "%.2f", previewCostPerLitre))/L")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(VineyardTheme.olive)
                        }
                    }
                }
            }
            .navigationTitle(purchase == nil ? "New Fuel Purchase" : "Edit Fuel Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let vol = Double(volumeText) ?? 0
        let cost = Double(costText) ?? 0
        if var existing = purchase {
            existing.volumeLitres = vol
            existing.totalCost = cost
            existing.date = date
            store.updateFuelPurchase(existing)
        } else {
            let newPurchase = FuelPurchase(volumeLitres: vol, totalCost: cost, date: date)
            store.addFuelPurchase(newPurchase)
        }
    }
}

struct AddEquipmentOptionSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let category: String

    @State private var value: String = ""

    private var categoryLabel: String {
        switch category {
        case SavedEquipmentOption.categoryEquipmentType: return "Equipment Type"
        case SavedEquipmentOption.categoryTractor: return "Tractor"
        case SavedEquipmentOption.categoryTractorGear: return "Tractor Gear"
        default: return "Option"
        }
    }

    private var isValid: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(categoryLabel, text: $value)
                }
            }
            .navigationTitle("Add \(categoryLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addEquipmentOption(SavedEquipmentOption(category: category, value: value.trimmingCharacters(in: .whitespacesAndNewlines)))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
