import SwiftUI

struct InviteMemberSheet: View {
    let vineyard: Vineyard
    @Environment(AuthService.self) private var authService
    @Environment(DataStore.self) private var store
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

    var body: some View {
        if !authService.pendingInvitations.isEmpty {
            Section {
                ForEach(authService.pendingInvitations) { invitation in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(invitation.vineyard_name ?? "Vineyard")
                                .font(.headline)
                            HStack(spacing: 4) {
                                Text("Role: \(invitation.role)")
                                if let inviter = invitation.invited_by_name {
                                    Text("from \(inviter)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    await authService.acceptInvitation(invitation)
                                    await cloudSync.pullAllData(for: store)
                                }
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(VineyardTheme.leafGreen)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task { await authService.declineInvitation(invitation) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.badge")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Pending Invitations")
                }
            }
        }
    }
}
