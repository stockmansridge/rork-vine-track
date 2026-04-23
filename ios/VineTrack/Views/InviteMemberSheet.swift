import SwiftUI

struct InviteMemberSheet: View {
    let vineyard: Vineyard
    @Environment(AuthService.self) private var authService
    @Environment(DataStore.self) private var store
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessControl) private var accessControl
    @State private var email: String = ""
    @State private var selectedRole: VineyardRole = .operator_
    @State private var selectedCategoryId: UUID? = nil
    @State private var isSending: Bool = false
    @State private var showSuccess: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Details") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("Role", selection: $selectedRole) {
                        ForEach(VineyardRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        RoleSummaryRow(title: "Operator", text: "Basic staff — records work, no deletes or financials.")
                        RoleSummaryRow(title: "Supervisor", text: "Manages day-to-day operations and deletes, no financials.")
                        RoleSummaryRow(title: "Manager", text: "Full access, including financials, setup and team.")
                    }
                    .padding(.vertical, 4)

                    NavigationLink {
                        RolesPermissionsInfoView()
                    } label: {
                        Label("Learn more about roles", systemImage: "info.circle")
                            .font(.footnote)
                    }
                } header: {
                    Text("Role")
                } footer: {
                    Text("Some features and values are hidden based on the assigned role.")
                }

                Section {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.operatorCategories) { cat in
                            if accessControl?.canViewFinancials ?? false {
                                Text("\(cat.name) ($\(String(format: "%.0f", cat.costPerHour))/hr)")
                                    .tag(UUID?.some(cat.id))
                            } else {
                                Text(cat.name)
                                    .tag(UUID?.some(cat.id))
                            }
                        }
                    }
                } header: {
                    Text("Operator Category")
                } footer: {
                    Text("Sets the hourly rate used in trip and task cost reports. You can change this later by tapping the user.")
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("The invited person will need to sign up or log in with this email to access the vineyard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if showSuccess {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(VineyardTheme.leafGreen)
                            Text("Invitation sent successfully!")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }

                if let error = authService.errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text("Error")
                    }
                }
            }
            .navigationTitle("Add User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendInvitation()
                    }
                    .disabled(email.isEmpty || isSending)
                }
            }
        }
    }

    private func sendInvitation() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("@") else {
            authService.errorMessage = "Please enter a valid email"
            return
        }

        authService.errorMessage = nil
        showSuccess = false
        isSending = true
        Task {
            // Ensure the vineyard exists in the cloud BEFORE creating the
            // invitation, so the vineyard_members FK is always satisfied
            // when the invitee accepts.
            try? await cloudSync.uploadVineyard(vineyard)

            let success = await authService.inviteMember(
                email: trimmed,
                role: selectedRole,
                vineyardId: vineyard.id,
                vineyardName: vineyard.name
            )
            let inviteError = authService.errorMessage
            await authService.loadSentInvitations(vineyardId: vineyard.id)
            if let inviteError, !success {
                authService.errorMessage = inviteError
            }
            isSending = false
            if success && authService.errorMessage == nil {
                showSuccess = true
                email = ""
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    dismiss()
                }
            }
        }
    }
}

struct PendingInvitationsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(DataStore.self) private var store
    @State private var activeInvitationId: UUID?
    @State private var localError: String?

    var body: some View {
        if !authService.pendingInvitations.isEmpty {
            Section {
                ForEach(authService.pendingInvitations) { invitation in
                    invitationRow(invitation)
                }
                if let localError {
                    Text(localError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.vertical, 4)
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.badge")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Pending Invitations")
                }
            } footer: {
                Text("If this email has been invited to another vineyard, accept it here to add that vineyard to your account.")
            }
        }
    }

    private func invitationRow(_ invitation: TeamInvitation) -> some View {
        let isProcessing: Bool = activeInvitationId == invitation.id

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(invitation.vineyard_name ?? "Vineyard")
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(invitation.role)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VineyardTheme.leafGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(VineyardTheme.leafGreen.opacity(0.12), in: Capsule())

                    if let inviter = invitation.invited_by_name, !inviter.isEmpty {
                        Text("Invited by \(inviter)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Accept to add this vineyard to your switcher.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
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
                        Text(isProcessing ? "Accepting…" : "Accept")
                    }
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
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(activeInvitationId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func acceptInvitation(_ invitation: TeamInvitation) async {
        activeInvitationId = invitation.id
        authService.errorMessage = nil
        localError = nil
        await authService.acceptInvitation(invitation)

        if let err = authService.errorMessage {
            localError = err
        } else {
            await cloudSync.pullAllData(for: store)
            await authService.loadPendingInvitations()
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
