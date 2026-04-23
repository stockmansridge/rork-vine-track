import SwiftUI

struct InvitationInboxView: View {
    @Environment(AuthService.self) private var authService
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(DataStore.self) private var store
    @State private var activeInvitationId: UUID?
    @State private var isRefreshing: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerCard

                    if let error = authService.errorMessage {
                        errorCard(message: error)
                    }

                    LazyVStack(spacing: 16) {
                        ForEach(authService.pendingInvitations) { invitation in
                            invitationCard(for: invitation)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invitations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        authService.signOut()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await refreshInvitations()
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || activeInvitationId != nil)
                }
            }
            .task {
                await refreshInvitations()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(VineyardTheme.leafGreen.opacity(0.14))
                        .frame(width: 52, height: 52)

                    Image(systemName: "envelope.badge.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(VineyardTheme.leafGreen)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("You’ve been invited")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("Accept an invitation below to join a vineyard and start working with the team right away.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !authService.userEmail.isEmpty {
                Label(authService.userEmail, systemImage: "person.crop.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func invitationCard(for invitation: TeamInvitation) -> some View {
        let isProcessing: Bool = activeInvitationId == invitation.id

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(invitation.vineyard_name ?? "Vineyard")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Label(invitation.role, systemImage: "person.badge.shield.checkmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VineyardTheme.leafGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(VineyardTheme.leafGreen.opacity(0.12), in: Capsule())

                    if let inviter = invitation.invited_by_name, !inviter.isEmpty {
                        Label("Invited by \(inviter)", systemImage: "person.crop.circle.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Accepting will add this vineyard to your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await acceptInvitation(invitation)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(isProcessing ? "Accepting…" : "Accept Invitation")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(VineyardTheme.leafGreen)
                .disabled(activeInvitationId != nil)

                Button(role: .destructive) {
                    Task {
                        await declineInvitation(invitation)
                    }
                } label: {
                    Label("Decline", systemImage: "xmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(activeInvitationId != nil)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22))
    }

    private func refreshInvitations() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await authService.loadPendingInvitations()
    }

    private func acceptInvitation(_ invitation: TeamInvitation) async {
        activeInvitationId = invitation.id
        authService.errorMessage = nil
        await authService.acceptInvitation(invitation)

        if authService.errorMessage == nil {
            await cloudSync.pullAllData(for: store)
            if let vineyardId = UUID(uuidString: invitation.vineyard_id),
               let vineyard = store.vineyards.first(where: { $0.id == vineyardId }) {
                store.selectVineyard(vineyard)
            }
        }

        activeInvitationId = nil
    }

    private func declineInvitation(_ invitation: TeamInvitation) async {
        activeInvitationId = invitation.id
        authService.errorMessage = nil
        await authService.declineInvitation(invitation)
        activeInvitationId = nil
    }
}
