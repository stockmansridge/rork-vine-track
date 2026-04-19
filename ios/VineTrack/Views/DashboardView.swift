import SwiftUI

struct DashboardView: View {
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService

    @State private var showPinDrop: Bool = false
    @State private var pinDropMode: PinMode = .repairs
    @State private var showYieldHub: Bool = false
    @State private var showGrowthStageReport: Bool = false
    @State private var showTripTypeChoice: Bool = false
    @State private var showStartSheet: Bool = false
    @State private var showSprayTripSetup: Bool = false
    @State private var showSprayCalculator: Bool = false
    @State private var showVineyardDetails: Bool = false
    @State private var showMaintenanceLog: Bool = false
    @State private var showWorkTaskCalculator: Bool = false
    @State private var showYieldDeterminationCalculator: Bool = false
    @Environment(\.accessControl) private var accessControl

    private var vineyard: Vineyard? { store.selectedVineyard }

    private var totalAreaHa: Double {
        store.paddocks.reduce(0) { $0 + $1.areaHectares }
    }

    private var totalVines: Int {
        store.paddocks.reduce(0) { $0 + $1.effectiveVineCount }
    }

    private var unresolvedPins: [VinePin] {
        store.pins.filter { !$0.isCompleted && $0.mode == .repairs }
    }

    private var lastCompletedTrip: Trip? {
        store.trips.filter { !$0.isActive }.sorted { $0.startTime > $1.startTime }.first
    }

    private var lastSprayRecord: SprayRecord? {
        store.sprayRecords.filter { !$0.isTemplate }.sorted { $0.date > $1.date }.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    vineyardSummaryCard
                    quickActionsSection
                    vineyardToolsSection
                    recentActivitySection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        if let logoData = vineyard?.logoData,
                           let uiImage = UIImage(data: logoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(.rect(cornerRadius: 6))
                        }
                        Text(vineyard?.name ?? "VineTrack")
                            .font(.headline)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showPinDrop) {
                PinDropView(initialMode: pinDropMode)
            }
            .navigationDestination(isPresented: $showYieldHub) {
                YieldHubView()
            }
            .navigationDestination(isPresented: $showGrowthStageReport) {
                GrowthStageReportView()
            }
            .navigationDestination(isPresented: $showVineyardDetails) {
                VineyardDetailsView()
            }
            .sheet(isPresented: $showTripTypeChoice) {
                TripTypeChoiceSheet { tripType in
                    showTripTypeChoice = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        switch tripType {
                        case .maintenance:
                            showStartSheet = true
                        case .spray:
                            showSprayTripSetup = true
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showStartSheet) {
                StartTripSheet()
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSprayTripSetup) {
                SprayTripSetupSheet(
                    onSelectProgram: { _ in
                        showSprayCalculator = true
                    },
                    onCreateNew: {
                        showSprayCalculator = true
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSprayCalculator, onDismiss: {
                showSprayTripSetup = false
            }) {
                SprayCalculatorView()
            }
            .navigationDestination(isPresented: $showMaintenanceLog) {
                MaintenanceLogListView()
            }
            .navigationDestination(isPresented: $showWorkTaskCalculator) {
                WorkTaskCalculatorView()
            }
            .navigationDestination(isPresented: $showYieldDeterminationCalculator) {
                YieldDeterminationCalculatorView()
            }
        }
    }

    // MARK: - Vineyard Summary

    private var vineyardSummaryCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vineyard Overview")
                        .font(.title3.weight(.bold))
                    if let name = vineyard?.name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.activeTrip != nil {
                    activeTripBadge
                }
            }
            .padding(.bottom, 16)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                summaryMetric(
                    value: "\(store.paddocks.count)",
                    label: "Blocks",
                    icon: "square.grid.2x2",
                    color: VineyardTheme.olive
                )
                summaryMetric(
                    value: String(format: "%.1f", totalAreaHa),
                    label: "Hectares",
                    icon: "map",
                    color: VineyardTheme.leafGreen
                )
                summaryMetric(
                    value: formatVineCount(totalVines),
                    label: "Vines",
                    icon: "leaf",
                    color: VineyardTheme.earthBrown
                )
            }

            Divider()
                .padding(.vertical, 14)

            HStack(spacing: 20) {
                miniStat(
                    icon: "mappin",
                    value: "\(unresolvedPins.count)",
                    label: "Open Pins",
                    color: .red
                )
                miniStat(
                    icon: "road.lanes",
                    value: "\(store.trips.filter { !$0.isActive }.count)",
                    label: "Trips",
                    color: .blue
                )
                miniStat(
                    icon: "sprinkler.and.droplets",
                    value: "\(store.sprayRecords.filter { !$0.isTemplate }.count)",
                    label: "Sprays",
                    color: .purple
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .onTapGesture {
            showVineyardDetails = true
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(16)
        }
    }

    private var activeTripBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text("Trip Active")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.green.opacity(0.12), in: Capsule())
    }

    private func summaryMetric(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func miniStat(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                quickActionButton(
                    title: "Repairs",
                    icon: "wrench.fill",
                    gradient: [Color.orange, Color.orange.opacity(0.8)]
                ) {
                    pinDropMode = .repairs
                    showPinDrop = true
                }

                quickActionButton(
                    title: "Growth",
                    iconView: AnyView(
                        GrapeLeafIcon(size: 22)
                            .foregroundStyle(.white)
                    ),
                    gradient: [VineyardTheme.leafGreen, VineyardTheme.olive]
                ) {
                    pinDropMode = .growth
                    showPinDrop = true
                }

                quickActionButton(
                    title: "Start Trip",
                    icon: "steeringwheel",
                    gradient: [Color.blue, Color.blue.opacity(0.8)]
                ) {
                    if store.activeTrip != nil {
                        store.selectedTab = 2
                    } else {
                        showTripTypeChoice = true
                    }
                }

                quickActionButton(
                    title: "Spray Program",
                    icon: "sprinkler.and.droplets.fill",
                    gradient: [Color.purple, Color.purple.opacity(0.8)]
                ) {
                    store.selectedTab = 3
                }
            }
        }
    }

    private func quickActionButton(
        title: String,
        icon: String? = nil,
        iconView: AnyView? = nil,
        gradient: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if let iconView {
                    iconView
                } else if let icon {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Vineyard Tools

    private var vineyardToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vineyard Tools")
                .font(.headline)

            HStack(spacing: 12) {
                toolCard(
                    title: "Yield Estimation",
                    subtitle: yieldToolSubtitle,
                    icon: "chart.bar.fill",
                    color: .orange
                ) {
                    showYieldHub = true
                }

                toolCard(
                    title: "Growth Stage Report",
                    subtitle: growthReportSubtitle,
                    icon: "chart.line.uptrend.xyaxis",
                    color: VineyardTheme.leafGreen
                ) {
                    showGrowthStageReport = true
                }
            }

            HStack(spacing: 12) {
                toolCard(
                    title: "Maintenance Log",
                    subtitle: maintenanceLogSubtitle,
                    icon: "wrench.and.screwdriver.fill",
                    color: VineyardTheme.earthBrown
                ) {
                    showMaintenanceLog = true
                }

                toolCard(
                    title: "Work Task Calculator",
                    subtitle: "Estimate labour cost",
                    icon: "person.2.badge.gearshape.fill",
                    color: .indigo
                ) {
                    showWorkTaskCalculator = true
                }
            }

            HStack(spacing: 12) {
                toolCard(
                    title: "Yield Determination",
                    subtitle: "Calculate yield per ha",
                    icon: "scalemass.fill",
                    color: .purple
                ) {
                    showYieldDeterminationCalculator = true
                }

                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }

    private var yieldToolSubtitle: String {
        let sessions = store.yieldSessions
        guard !sessions.isEmpty else { return "No estimates yet" }
        let blocksWithData = Set(sessions.flatMap(\.selectedPaddockIds)).count
        return "\(blocksWithData) block\(blocksWithData == 1 ? "" : "s") estimated"
    }

    private var growthReportSubtitle: String {
        let growthPins = store.pins.filter { $0.growthStageCode != nil }
        guard !growthPins.isEmpty else { return "No data recorded" }
        return "\(growthPins.count) observation\(growthPins.count == 1 ? "" : "s")"
    }

    private func toolCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color.opacity(0.8))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 170)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }


    private var maintenanceLogSubtitle: String {
        let logs = store.maintenanceLogs
        guard !logs.isEmpty else { return "No records yet" }
        let total = logs.reduce(0) { $0 + $1.totalCost }
        let currencyCode = Locale.current.currency?.identifier ?? "USD"
        return "\(logs.count) record\(logs.count == 1 ? "" : "s") \u{2022} \(total.formatted(.currency(code: currencyCode)))"
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)

            VStack(spacing: 1) {
                if let trip = lastCompletedTrip {
                    recentRow(
                        icon: "steeringwheel",
                        iconColor: .blue,
                        title: "Last Trip",
                        detail: trip.paddockName.isEmpty ? "Trip" : trip.paddockName,
                        time: trip.endTime ?? trip.startTime,
                        distance: trip.totalDistance
                    )
                }

                if let spray = lastSprayRecord {
                    recentRow(
                        icon: "sprinkler.and.droplets.fill",
                        iconColor: .purple,
                        title: "Last Spray",
                        detail: spray.sprayReference.isEmpty ? "Spray Record" : spray.sprayReference,
                        time: spray.date,
                        distance: nil
                    )
                }

                if !unresolvedPins.isEmpty {
                    unresolvedPinsRow
                }

                if lastCompletedTrip == nil && lastSprayRecord == nil && unresolvedPins.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("No recent activity")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }
            }
        }
    }

    private func recentRow(
        icon: String,
        iconColor: Color,
        title: String,
        detail: String,
        time: Date,
        distance: Double?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.1), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let distance, distance > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.1f km", distance / 1000))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(time, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var unresolvedPinsRow: some View {
        Button {
            store.selectedTab = 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
                    .background(.red.opacity(0.1), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unresolved Pins")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(unresolvedPins.count) repair\(unresolvedPins.count == 1 ? "" : "s") pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatVineCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
