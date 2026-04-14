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
                .task {
                    locationService.requestPermission()
                    store.cloudSync = cloudSync
                    store.analytics = analytics
                    tripTrackingService.configure(store: store, locationService: locationService)
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
}
