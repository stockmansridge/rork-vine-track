import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(AnalyticsService.self) private var analytics
    @Environment(AdminService.self) private var adminService
    @Environment(StoreViewModel.self) private var storeVM
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var showAdminDashboard: Bool = false
    @State private var showVineyardList: Bool = false
    @State private var showVineyardDetail: Bool = false
    @State private var showSupportForm: Bool = false
    @State private var showPaywall: Bool = false


    var body: some View {
        NavigationStack {
            Form {
                if adminService.isAdmin {
                    adminSection
                }

                subscriptionSection
                PendingInvitationsView()
                vineyardSection
                setupSection
                yieldEstimationSection
                reportsSection
                accountNavSection
                supportSection
                appInfoSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAdminDashboard) {
                AdminDashboardView()
            }
            .sheet(isPresented: $showVineyardList) {
                VineyardListView()
            }
            .sheet(isPresented: $showVineyardDetail) {
                if let vineyard = store.selectedVineyard {
                    VineyardDetailSheet(vineyard: vineyard)
                }
            }
            .sheet(isPresented: $showSupportForm) {
                SupportFormView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task {
                await adminService.checkAdminStatus()
            }
        }
    }

    private var subscriptionSection: some View {
        Section {
            if storeVM.isPremium {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.green.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VineTrack Pro")
                            .font(.subheadline.weight(.medium))
                        Text("You have full access")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(VineyardTheme.leafGreen)
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.green.gradient)
                                .frame(width: 32, height: 32)
                            Image(systemName: "star.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Pro")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Unlock all features")
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

            Button {
                Task { await storeVM.restore() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text("Subscription")
            }
        }
    }

    private var adminSection: some View {
        Section {
            Button {
                showAdminDashboard = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Admin Dashboard")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("View all users & analytics")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text("Administration")
            }
        }
    }

    private var vineyardSection: some View {
        Section {
            if let vineyard = store.selectedVineyard {
                HStack(spacing: 12) {
                    if let logoData = vineyard.logoData,
                       let uiImage = UIImage(data: logoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(.rect(cornerRadius: 8))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green.gradient)
                                .frame(width: 40, height: 40)
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vineyard.name)
                            .font(.headline)
                        Text("\(vineyard.users.count) user\(vineyard.users.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

            PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                Label(store.selectedVineyard?.logoData != nil ? "Change Logo" : "Add Logo", systemImage: "photo.badge.plus")
                    .foregroundStyle(.primary)
            }
            .onChange(of: selectedLogoItem) { _, newItem in
                handleLogoSelection(newItem)
            }

            if store.selectedVineyard?.logoData != nil {
                Button(role: .destructive) {
                    store.updateVineyardLogo(nil)
                } label: {
                    Label("Remove Logo", systemImage: "trash")
                }
            }

            Button {
                showVineyardDetail = true
            } label: {
                Label("Manage Vineyard", systemImage: "person.2")
                    .foregroundStyle(.primary)
            }

            Button {
                showVineyardList = true
            } label: {
                Label("Switch Vineyard", systemImage: "arrow.triangle.swap")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("Current Vineyard")
        }
    }

    private var setupSection: some View {
        Section {
            NavigationLink {
                VineyardSetupSettingsView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(VineyardTheme.leafGreen.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "leaf.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vineyard Setup")
                            .font(.subheadline.weight(.medium))
                        Text("Blocks, buttons & growth stages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                SprayManagementSettingsView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.teal.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "sprinkler.and.droplets.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spray Management")
                            .font(.subheadline.weight(.medium))
                        Text("Presets, chemicals & equipment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                PreferencesSettingsView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.indigo.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preferences")
                            .font(.subheadline.weight(.medium))
                        Text("Season, tracking, photos & timezone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                DataPrivacySettingsView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.orange.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "externaldrive.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Data Management")
                            .font(.subheadline.weight(.medium))
                        Text("Backup, pins, trips & storage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(VineyardTheme.olive)
                    .font(.caption)
                Text("Manage")
            }
        }
    }

    private var yieldEstimationSection: some View {
        Section {
            NavigationLink {
                YieldEstimationView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.purple.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Yield Estimation")
                            .font(.subheadline.weight(.medium))
                        Text("Bunch count sample sites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                YieldReportsListView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.indigo.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "list.clipboard.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Yield Reports")
                            .font(.subheadline.weight(.medium))
                        Text("Block summaries & estimation jobs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                DamageRecordsListView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Record Damage")
                            .font(.subheadline.weight(.medium))
                        let count = store.damageRecords.count
                        Text(count > 0 ? "\(count) damage record\(count == 1 ? "" : "s")" : "Frost, hail, wind & more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundStyle(.purple)
                    .font(.caption)
                Text("Yield Estimation")
            }
        }
    }

    private var reportsSection: some View {
        Section {
            NavigationLink {
                GrowthStageReportView()
            } label: {
                HStack {
                    Label("Growth Stage Report", systemImage: "chart.bar.xaxis")
                        .foregroundStyle(.primary)
                    Spacer()
                    let count = store.pins.filter { $0.growthStageCode != nil && $0.mode == .growth }.count
                    if count > 0 {
                        Text("\(count) entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.purple)
                    .font(.caption)
                Text("Reports")
            }
        }
    }

    private var accountNavSection: some View {
        Section {
            NavigationLink {
                AccountSettingsView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.gray.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "person.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Account")
                            .font(.subheadline.weight(.medium))
                        Text(authService.userName.isEmpty ? "Sign out & manage account" : authService.userName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .foregroundStyle(.gray)
                    .font(.caption)
                Text("Account")
            }
        }
    }

    private var supportSection: some View {
        Section {
            Button {
                showSupportForm = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.blue.gradient)
                            .frame(width: 32, height: 32)
                        Image(systemName: "envelope.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contact Support")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Report an issue or send feedback")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text("Support")
            }
        }
    }

    private var appInfoSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
        } header: {
            Text("About")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func handleLogoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let maxSize: CGFloat = 200
                let scale = min(maxSize / uiImage.size.width, maxSize / uiImage.size.height, 1.0)
                let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                let resized = renderer.image { _ in
                    uiImage.draw(in: CGRect(origin: .zero, size: newSize))
                }
                if let compressed = resized.jpegData(compressionQuality: 0.7) {
                    store.updateVineyardLogo(compressed)
                }
            }
            selectedLogoItem = nil
        }
    }
}

struct TimezonePicker: View {
    @Binding var selectedTimezone: String
    @State private var searchText: String = ""

    private var timezones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(timezones, id: \.self) { tz in
                Button {
                    selectedTimezone = tz
                } label: {
                    HStack {
                        Text(tz.replacingOccurrences(of: "_", with: " "))
                            .foregroundStyle(.primary)
                        Spacer()
                        if tz == selectedTimezone {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search timezones")
        .navigationTitle("Timezone")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NearbyStationPicker: View {
    let weatherStationService: WeatherStationService
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if weatherStationService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Searching for nearby stations...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = weatherStationService.errorMessage {
                    ContentUnavailableView {
                        Label("Unable to Find Stations", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if weatherStationService.nearbyStations.isEmpty {
                    ContentUnavailableView {
                        Label("No Stations Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("No Weather Underground personal weather stations were found near your location.")
                    }
                } else {
                    List {
                        ForEach(weatherStationService.nearbyStations) { station in
                            Button {
                                onSelect(station.id)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(station.id)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if !station.name.isEmpty && station.name != station.id {
                                            Text(station.name)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(station.localizedDistance)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nearby Stations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
