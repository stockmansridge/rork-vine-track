import SwiftUI

struct VineyardListView: View {
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(\.accessControl) private var accessControl
    @State private var showAddVineyard: Bool = false

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddVineyard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddVineyard) {
                EditVineyardSheet(vineyard: nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            GrapeLeafIcon(size: 64)
                .foregroundStyle(VineyardTheme.leafGreen.opacity(0.6))

            VStack(spacing: 8) {
                Text("Welcome to VineTrack")
                    .font(.title2.weight(.semibold))
                Text("Create your first vineyard to get started. All blocks, pins, trips, and settings belong to a vineyard.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
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
                                    store.deleteVineyard(vineyard)
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
