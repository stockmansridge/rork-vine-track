import SwiftUI

struct VineyardCostsSection: View {
    @Environment(DataStore.self) private var store
    @Environment(\.accessControl) private var accessControl

    @State private var selectedCategory: CostCategory?

    enum CostCategory: String, Identifiable, CaseIterable {
        case chemicals, fuel, operatorCost, maintenance, workTasks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chemicals: return "Chemicals"
            case .fuel: return "Fuel"
            case .operatorCost: return "Operator"
            case .maintenance: return "Maintenance"
            case .workTasks: return "Work Tasks"
            }
        }

        var icon: String {
            switch self {
            case .chemicals: return "flask.fill"
            case .fuel: return "fuelpump.fill"
            case .operatorCost: return "person.fill"
            case .maintenance: return "wrench.and.screwdriver.fill"
            case .workTasks: return "person.2.badge.gearshape.fill"
            }
        }

        var color: Color {
            switch self {
            case .chemicals: return .purple
            case .fuel: return .orange
            case .operatorCost: return .blue
            case .maintenance: return VineyardTheme.earthBrown
            case .workTasks: return .indigo
            }
        }
    }

    private var seasonStartDate: Date {
        let cal = Calendar.current
        let now = Date()
        let month = store.settings.seasonStartMonth
        let day = store.settings.seasonStartDay
        let currentMonth = cal.component(.month, from: now)
        let currentDay = cal.component(.day, from: now)
        let year = cal.component(.year, from: now)
        let startYear: Int
        if currentMonth > month || (currentMonth == month && currentDay >= day) {
            startYear = year
        } else {
            startYear = year - 1
        }
        return cal.date(from: DateComponents(year: startYear, month: month, day: day)) ?? now
    }

    private var seasonTrips: [Trip] {
        store.trips.filter { !$0.isActive && $0.startTime >= seasonStartDate }
    }

    private var seasonMaintenance: [MaintenanceLog] {
        store.maintenanceLogs.filter { $0.date >= seasonStartDate }
    }

    private func chemicalCost(for trip: Trip) -> Double {
        let record = store.sprayRecord(for: trip.id)
        return (record?.tanks ?? []).flatMap { $0.chemicals }
            .reduce(0.0) { $0 + ($1.costPerUnit * $1.volumePerTank) }
    }

    private func fuelCost(for trip: Trip) -> Double {
        guard let record = store.sprayRecord(for: trip.id) else { return 0 }
        let tractor = store.tractors.first(where: { $0.displayName == record.tractor || $0.name == record.tractor })
        guard let tractor, tractor.fuelUsageLPerHour > 0 else { return 0 }
        let fuelPrice = store.seasonFuelCostPerLitre
        guard fuelPrice > 0 else { return 0 }
        return fuelPrice * tractor.fuelUsageLPerHour * (trip.activeDuration / 3600.0)
    }

    private func operatorCost(for trip: Trip) -> Double {
        guard !trip.personName.isEmpty,
              let category = store.operatorCategoryForName(trip.personName),
              category.costPerHour > 0 else { return 0 }
        return category.costPerHour * (trip.activeDuration / 3600.0)
    }

    private var seasonWorkTasks: [WorkTask] {
        store.workTasks.filter { $0.date >= seasonStartDate }
    }

    private var totalChemicals: Double { seasonTrips.reduce(0) { $0 + chemicalCost(for: $1) } }
    private var totalFuel: Double { seasonTrips.reduce(0) { $0 + fuelCost(for: $1) } }
    private var totalOperator: Double { seasonTrips.reduce(0) { $0 + operatorCost(for: $1) } }
    private var totalMaintenance: Double { seasonMaintenance.reduce(0) { $0 + $1.totalCost } }
    private var totalWorkTasks: Double { seasonWorkTasks.reduce(0) { $0 + $1.totalCost } }
    private var grandTotal: Double { totalChemicals + totalFuel + totalOperator + totalMaintenance + totalWorkTasks }

    var body: some View {
        if accessControl?.canViewFinancials ?? false {
            contentBody
        } else {
            restrictedCard
        }
    }

    private var restrictedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Financial data hidden")
                    .font(.subheadline.weight(.semibold))
                Text("Only Managers can view season costs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Season Costs")
                    .font(.headline)
                Spacer()
                Text(formatCurrency(grandTotal))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(VineyardTheme.leafGreen)
            }

            VStack(spacing: 8) {
                costRow(.chemicals, value: totalChemicals)
                costRow(.fuel, value: totalFuel)
                costRow(.operatorCost, value: totalOperator)
                costRow(.maintenance, value: totalMaintenance)
                costRow(.workTasks, value: totalWorkTasks)
            }

            Text("Tap a category to see a breakdown by paddock.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $selectedCategory) { category in
            CostBreakdownSheet(
                category: category,
                seasonStartDate: seasonStartDate
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func costRow(_ category: CostCategory, value: Double) -> some View {
        Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundStyle(category.color)
                    .frame(width: 36, height: 36)
                    .background(category.color.opacity(0.12), in: .rect(cornerRadius: 10))

                Text(category.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text(formatCurrency(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func formatCurrency(_ value: Double) -> String {
        value > 0 ? String(format: "$%.2f", value) : "–"
    }
}

// MARK: - Breakdown Sheet

private struct CostBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    let category: VineyardCostsSection.CostCategory
    let seasonStartDate: Date

    private var paddocks: [Paddock] { store.orderedPaddocks }

    private var seasonTrips: [Trip] {
        store.trips.filter { !$0.isActive && $0.startTime >= seasonStartDate }
    }

    private var seasonMaintenance: [MaintenanceLog] {
        store.maintenanceLogs.filter { $0.date >= seasonStartDate }
    }

    private var seasonWorkTasks: [WorkTask] {
        store.workTasks.filter { $0.date >= seasonStartDate }
    }

    private func tripTotal(_ trip: Trip) -> Double {
        switch category {
        case .chemicals:
            let record = store.sprayRecord(for: trip.id)
            return (record?.tanks ?? []).flatMap { $0.chemicals }
                .reduce(0.0) { $0 + ($1.costPerUnit * $1.volumePerTank) }
        case .fuel:
            guard let record = store.sprayRecord(for: trip.id) else { return 0 }
            let tractor = store.tractors.first(where: { $0.displayName == record.tractor || $0.name == record.tractor })
            guard let tractor, tractor.fuelUsageLPerHour > 0 else { return 0 }
            let fuelPrice = store.seasonFuelCostPerLitre
            guard fuelPrice > 0 else { return 0 }
            return fuelPrice * tractor.fuelUsageLPerHour * (trip.activeDuration / 3600.0)
        case .operatorCost:
            guard !trip.personName.isEmpty,
                  let cat = store.operatorCategoryForName(trip.personName),
                  cat.costPerHour > 0 else { return 0 }
            return cat.costPerHour * (trip.activeDuration / 3600.0)
        case .maintenance:
            return 0
        case .workTasks:
            return 0
        }
    }

    private struct PaddockCost: Identifiable {
        let id: UUID
        let name: String
        let amount: Double
    }

    private var breakdown: [PaddockCost] {
        if category == .maintenance {
            let total = seasonMaintenance.reduce(0) { $0 + $1.totalCost }
            let totalArea = paddocks.reduce(0) { $0 + $1.areaHectares }
            guard total > 0, totalArea > 0 else {
                return paddocks.map { PaddockCost(id: $0.id, name: $0.name, amount: 0) }
            }
            return paddocks.map { p in
                let share = p.areaHectares / totalArea
                return PaddockCost(id: p.id, name: p.name, amount: total * share)
            }.sorted { $0.amount > $1.amount }
        }

        if category == .workTasks {
            var totals: [UUID: Double] = [:]
            var unassigned: Double = 0
            for task in seasonWorkTasks {
                let amount = task.totalCost
                guard amount > 0 else { continue }
                if let pid = task.paddockId, paddocks.contains(where: { $0.id == pid }) {
                    totals[pid, default: 0] += amount
                } else {
                    unassigned += amount
                }
            }
            if unassigned > 0 {
                let totalArea = paddocks.reduce(0) { $0 + $1.areaHectares }
                if totalArea > 0 {
                    for p in paddocks {
                        totals[p.id, default: 0] += unassigned * (p.areaHectares / totalArea)
                    }
                }
            }
            return paddocks.map { p in
                PaddockCost(id: p.id, name: p.name, amount: totals[p.id] ?? 0)
            }.sorted { $0.amount > $1.amount }
        }

        var totals: [UUID: Double] = [:]
        for trip in seasonTrips {
            let amount = tripTotal(trip)
            guard amount > 0 else { continue }

            let ids: [UUID] = !trip.paddockIds.isEmpty ? trip.paddockIds : (trip.paddockId.map { [$0] } ?? [])
            let tripPaddocks = paddocks.filter { ids.contains($0.id) }
            guard !tripPaddocks.isEmpty else { continue }

            let totalArea = tripPaddocks.reduce(0) { $0 + $1.areaHectares }
            if totalArea > 0 {
                for p in tripPaddocks {
                    totals[p.id, default: 0] += amount * (p.areaHectares / totalArea)
                }
            } else {
                let share = amount / Double(tripPaddocks.count)
                for p in tripPaddocks {
                    totals[p.id, default: 0] += share
                }
            }
        }

        return paddocks.map { p in
            PaddockCost(id: p.id, name: p.name, amount: totals[p.id] ?? 0)
        }.sorted { $0.amount > $1.amount }
    }

    private var total: Double { breakdown.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundStyle(category.color)
                        Text("Season Total")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(total > 0 ? String(format: "$%.2f", total) : "–")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }

                Section("By Paddock") {
                    if breakdown.isEmpty {
                        Text("No paddocks")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(breakdown) { item in
                            paddockRow(item)
                        }
                    }
                }

                if category == .maintenance {
                    Section {
                        Text("Maintenance costs are vineyard-wide and distributed across paddocks by area.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if category == .workTasks {
                    Section {
                        Text("Work task costs are assigned to their block. Tasks with no block are distributed across paddocks by area.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func paddockRow(_ item: PaddockCost) -> some View {
        HStack(spacing: 12) {
            GrapeLeafIcon(size: 14)
                .foregroundStyle(VineyardTheme.olive)

            Text(item.name)
                .font(.subheadline)

            Spacer()

            if total > 0 {
                Text("\(Int((item.amount / total) * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(item.amount > 0 ? String(format: "$%.2f", item.amount) : "–")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}
