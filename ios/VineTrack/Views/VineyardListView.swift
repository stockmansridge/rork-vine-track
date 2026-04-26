import SwiftUI

struct VineyardListView: View {
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(\.accessControl) private var accessControl
    @State private var showAddVineyard: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var vineyardPendingDeletion: Vineyard?

    var body: some View {
        NavigationStack {
            Group {
                if store.vineyards.isEmpty && authService.pendingInvitations.isEmpty {
                    emptyState
                } else {
                    vineyardList
                }
            }
            .navigationTitle("Vineyards")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refreshInvitations() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddVineyard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await refreshInvitations() }
            .sheet(isPresented: $showAddVineyard) {
                EditVineyardSheet(vineyard: nil)
            }
            .task { await refreshInvitations() }
            .deleteVineyardConfirmation(vineyardPendingDeletion: $vineyardPendingDeletion) { vineyard in
                store.deleteVineyard(vineyard)
            }
        }
    }

    private func refreshInvitations() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await authService.loadPendingInvitations()
        await cloudSync.claimVineyardsByEmail()
        await cloudSync.pullAllData(for: store)
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            GrapeLeafIcon(size: 64)
                .foregroundStyle(VineyardTheme.leafGreen.opacity(0.6))

            VStack(spacing: 8) {
                Text("Welcome to VineTrack")
                    .font(.title2.weight(.semibold))
                Text("Create your first vineyard to get started, or check for a pending invitation below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                if !authService.userEmail.isEmpty {
                    Text("Signed in as \(authService.userEmail)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                showAddVineyard = true
            } label: {
                Label("Create Vineyard", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(VineyardTheme.olive)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Button {
                Task { await refreshInvitations() }
            } label: {
                if isRefreshing {
                    ProgressView()
                } else {
                    Label("Check for invitations", systemImage: "envelope.badge")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .disabled(isRefreshing)

            Button(role: .destructive) {
                authService.signOut()
            } label: {
                Label("Back to Login", systemImage: "arrow.backward.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 40)

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var vineyardList: some View {
        List {
            PendingInvitationsView()

            if store.vineyards.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("No vineyards yet")
                            .font(.headline)
                        Text("Accept a pending invitation above, or create your first vineyard.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showAddVineyard = true
                        } label: {
                            Label("Create Vineyard", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VineyardTheme.olive)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                ForEach(store.vineyards) { vineyard in
                    VineyardCardRow(vineyard: vineyard, isSelected: vineyard.id == store.selectedVineyardId)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if accessControl?.canDelete ?? false {
                                Button(role: .destructive) {
                                    vineyardPendingDeletion = vineyard
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct VineyardCardRow: View {
    let vineyard: Vineyard
    let isSelected: Bool
    @Environment(DataStore.self) private var store
    @State private var showEdit: Bool = false
    @State private var showDetail: Bool = false

    var body: some View {
        Button {
            store.selectVineyard(vineyard)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? VineyardTheme.leafGreen.gradient : Color(.tertiarySystemFill).gradient)
                        .frame(width: 44, height: 44)

                    GrapeLeafIcon(size: 22)
                        .foregroundStyle(isSelected ? .white : VineyardTheme.leafGreen)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(vineyard.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Label("\(vineyard.users.count)", systemImage: "person.2")
                        if isSelected {
                            Text("Active")
                                .fontWeight(.medium)
                                .foregroundStyle(VineyardTheme.leafGreen)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            VineyardDetailSheet(vineyard: vineyard)
        }
    }
}
