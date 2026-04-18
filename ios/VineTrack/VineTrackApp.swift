import SwiftUI
import RevenueCat

@main
struct VineTrackApp: App {
    @State private var store = DataStore()
    @State private var locationService = LocationService()
    @State private var authService = AuthService()
    @State private var cloudSync = CloudSyncService()
    @State private var analytics = AnalyticsService()
    @State private var adminService = AdminService()
    @State private var tripTrackingService = TripTrackingService()
    @State private var storeViewModel = StoreViewModel()
    @State private var degreeDayService = DegreeDayService()
    @State private var accessControl: AccessControl?

    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_TEST_API_KEY)
        #else
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(locationService)
                .environment(authService)
                .environment(cloudSync)
                .environment(analytics)
                .environment(adminService)
                .environment(tripTrackingService)
                .environment(storeViewModel)
                .environment(degreeDayService)
                .environment(\.accessControl, accessControl)
                .task {
                    accessControl = AccessControl(store: store, authService: authService)
                    locationService.requestPermission()
                    store.cloudSync = cloudSync
                    store.analytics = analytics
                    tripTrackingService.configure(store: store, locationService: locationService)
                    await refreshDailyGDDIfNeeded()
                }
                .onChange(of: store.selectedVineyardId) { _, _ in
                    Task { await refreshDailyGDDIfNeeded() }
                }
                .onAppear {
                    authService.restorePreviousSignIn()
                }
                .preferredColorScheme(store.settings.appearance.colorScheme)
                .onOpenURL { url in
                    _ = authService.handleURL(url)
                }
                .onChange(of: authService.isSignedIn) { oldValue, isSignedIn in
                    if isSignedIn {
                        if !authService.isDemoMode {
                            store.load()
                        }
                        analytics.setUser(authService.userId)
                        analytics.track("user_signed_in")
                        Task {
                            await cloudSync.pullAllData(for: store)
                            await cloudSync.startRealtime(for: store)
                            await authService.loadPendingInvitations()
                        await adminService.checkAdminStatus()
                        }
                    } else {
                        if oldValue && !authService.isDemoMode {
                            store.clearInMemoryState()
                        }
                        Task {
                            await cloudSync.stopRealtime()
                        }
                    }
                }
                .onChange(of: authService.isDemoMode) { oldValue, isDemoMode in
                    if oldValue && !isDemoMode {
                        store.deleteAllData()
                    }
                }
        }
    }

    private func refreshDailyGDDIfNeeded() async {
        guard let stationId = store.settings.weatherStationId, !stationId.isEmpty else { return }
        guard degreeDayService.needsDailyRefresh(for: stationId) else { return }
        await degreeDayService.fetchSeasonGDD(stationId: stationId, seasonStart: currentSeasonStart())
    }

    private func currentSeasonStart() -> Date {
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
}
