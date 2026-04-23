import SwiftUI
import RevenueCat
import BackgroundTasks

@main
struct VineTrackApp: App {
    @State private var store: DataStore
    @State private var locationService = LocationService()
    @State private var authService: AuthService
    @State private var cloudSync = CloudSyncService()
    @State private var analytics = AnalyticsService()
    @State private var adminService = AdminService()
    @State private var tripTrackingService = TripTrackingService()
    @State private var storeViewModel = StoreViewModel()
    @State private var degreeDayService = DegreeDayService()
    @State private var accessControl: AccessControl
    @State private var auditService = AuditService()
    @State private var rainAlertService = RainAlertService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        RainAlertService.registerBackgroundTask { task in
            Task { @MainActor in
                await Self.handleBackgroundRainCheck(task: task)
            }
        }
        let s = DataStore()
        let a = AuthService()
        _store = State(initialValue: s)
        _authService = State(initialValue: a)
        _accessControl = State(initialValue: AccessControl(store: s, authService: a))
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
                .environment(auditService)
                .environment(rainAlertService)
                .task {
                    locationService.requestPermission()
                    store.cloudSync = cloudSync
                    store.analytics = analytics
                    store.auditService = auditService
                    store.authService = authService
                    store.accessControl = accessControl
                    auditService.configure(store: store, authService: authService, accessControl: accessControl)
                    tripTrackingService.configure(store: store, locationService: locationService)
                    await refreshDailyGDDIfNeeded()
                    await rainAlertService.refreshAuthorizationStatus()
                    await runRainAlertCheckIfNeeded()
                    if store.settings.rainAlertEnabled {
                        rainAlertService.scheduleDailyBackgroundCheck()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background, store.settings.rainAlertEnabled {
                        rainAlertService.scheduleDailyBackgroundCheck()
                    }
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
                .sheet(isPresented: Binding(
                    get: { authService.showPasswordRecovery },
                    set: { authService.showPasswordRecovery = $0 }
                )) {
                    PasswordRecoveryView()
                        .environment(authService)
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

    private func runRainAlertCheckIfNeeded() async {
        guard store.settings.rainAlertEnabled else { return }
        let lat = store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
        let lon = store.settings.vineyardLongitude ?? store.paddockCentroidLongitude
        guard let lat, let lon else { return }
        if let last = rainAlertService.lastCheckDate,
           Calendar.current.isDateInToday(last) {
            return
        }
        await rainAlertService.checkForecastAndNotify(
            latitude: lat,
            longitude: lon,
            windowDays: store.settings.rainAlertWindowDays,
            thresholdMm: store.settings.rainAlertThresholdMm
        )
    }

    @MainActor
    static func handleBackgroundRainCheck(task: BGAppRefreshTask) async {
        let service = RainAlertService()
        let store = DataStore()
        store.load()

        let settings = store.settings
        guard settings.rainAlertEnabled else {
            task.setTaskCompleted(success: true)
            return
        }
        let lat = settings.vineyardLatitude ?? store.paddockCentroidLatitude
        let lon = settings.vineyardLongitude ?? store.paddockCentroidLongitude
        guard let lat, let lon else {
            task.setTaskCompleted(success: true)
            return
        }

        service.scheduleDailyBackgroundCheck()

        let checkTask = Task {
            await service.checkForecastAndNotify(
                latitude: lat,
                longitude: lon,
                windowDays: settings.rainAlertWindowDays,
                thresholdMm: settings.rainAlertThresholdMm
            )
        }

        task.expirationHandler = {
            checkTask.cancel()
        }

        await checkTask.value
        task.setTaskCompleted(success: true)
    }

    private func refreshDailyGDDIfNeeded() async {
        guard let stationId = store.settings.weatherStationId, !stationId.isEmpty else { return }
        guard degreeDayService.needsDailyRefresh(for: stationId) else { return }
        await degreeDayService.fetchSeasonGDD(
            stationId: stationId,
            seasonStart: currentSeasonStart(),
            latitude: store.settings.vineyardLatitude ?? store.paddockCentroidLatitude,
            useBEDD: store.settings.calculationMode.useBEDD
        )
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
