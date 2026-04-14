import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(CloudSyncService.self) private var cloudSync
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var hasAcceptedDisclaimer: Bool = false
    @State private var isCheckingDisclaimer: Bool = false

    var body: some View {
        Group {
            if authService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            } else if !authService.isSignedIn {
                LoginView()
            } else if !hasCompletedOnboarding && !authService.isDemoMode {
                OnboardingView {
                    withAnimation(.smooth) {
                        hasCompletedOnboarding = true
                    }
                }
            } else if !hasAcceptedDisclaimer && !authService.isDemoMode {
                if isCheckingDisclaimer {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                } else {
                    DisclaimerView {
                        withAnimation(.smooth) {
                            hasAcceptedDisclaimer = true
                        }
                    }
                }
            } else if store.vineyards.isEmpty {
                VineyardListView()
            } else {
                mainTabView
            }
        }
        .onChange(of: authService.isLoading) { _, isLoading in
            if !isLoading, authService.isSignedIn, let userId = authService.userId {
                let name = authService.userName.isEmpty ? authService.userEmail : authService.userName
                store.backfillVineyardOwner(userId: userId, userName: name)
            }
        }
        .onChange(of: authService.isDemoMode) { _, isDemoMode in
            if isDemoMode {
                hasAcceptedDisclaimer = true
                store.loadDemoData()
            }
        }
        .onChange(of: authService.isSignedIn) { _, isSignedIn in
            if isSignedIn, !authService.isDemoMode, let userId = authService.userId {
                let localKey = "vinetrack_disclaimer_accepted_\(userId)"
                if UserDefaults.standard.bool(forKey: localKey) {
                    hasAcceptedDisclaimer = true
                } else {
                    isCheckingDisclaimer = true
                    Task {
                        let accepted = await AdminService().checkDisclaimerAccepted(userId: userId)
                        if accepted {
                            UserDefaults.standard.set(true, forKey: localKey)
                        }
                        hasAcceptedDisclaimer = accepted
                        isCheckingDisclaimer = false
                    }
                }
            } else if !isSignedIn {
                hasAcceptedDisclaimer = false
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: Bindable(store).selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                HomeView()
            }
            Tab("Pins", systemImage: "mappin.and.ellipse", value: 1) {
                PinsView()
            }
            Tab("Trip", systemImage: "steeringwheel", value: 2) {
                TripView()
            }
            Tab("Program", systemImage: "sprinkler.and.droplets.fill", value: 3) {
                SprayProgramView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: 4) {
                SettingsView()
            }
        }
    }
}
