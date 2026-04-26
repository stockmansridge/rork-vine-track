import SwiftUI

struct ContentView: View {
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(CloudSyncService.self) private var cloudSync
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var hasAcceptedDisclaimer: Bool = false
    @State private var isCheckingDisclaimer: Bool = false
    @State private var isLoadingInitialCloudData: Bool = false

    var body: some View {
        Group {
            if authService.isLoading || authService.isAuthenticating {
                ProgressView(authService.isAuthenticating ? "Signing in…" : "")
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
            } else if store.vineyards.isEmpty && !authService.pendingInvitations.isEmpty {
                InvitationInboxView()
            } else if isLoadingInitialCloudData && store.vineyards.isEmpty && !authService.isDemoMode {
                syncingState
            } else if store.vineyards.isEmpty {
                VineyardListView()
            } else if store.selectedVineyard == nil {
                // Multiple vineyards available but none selected (e.g.
                // first sign-in on a fresh device, or after switching
                // accounts). Let the user pick which vineyard to enter.
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
                runInitialCloudLoadIfNeeded()
            } else if !isSignedIn {
                hasAcceptedDisclaimer = false
                isCheckingDisclaimer = false
                isLoadingInitialCloudData = false
            }
        }
    }

    private var syncingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading your vineyards…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Continue") {
                isLoadingInitialCloudData = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func runInitialCloudLoadIfNeeded() {
        guard authService.isSignedIn, !authService.isDemoMode else { return }
        guard !isLoadingInitialCloudData else { return }
        isLoadingInitialCloudData = true
        Task {
            await authService.loadPendingInvitations()
            await cloudSync.claimVineyardsByEmail()
            await cloudSync.pullAllData(for: store)
            if store.vineyards.isEmpty {
                await cloudSync.claimVineyardsByEmail()
                await cloudSync.pullAllData(for: store)
            }
            await cloudSync.startRealtime(for: store)
            isLoadingInitialCloudData = false
        }
    }

    private var mainTabView: some View {
        TabView(selection: Bindable(store).selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                DashboardView()
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
