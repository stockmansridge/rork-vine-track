import SwiftUI

struct InviteMemberSheet: View {
    let vineyard: Vineyard
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var selectedRole: VineyardRole = .member
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

                    Picker("Role", selection: $selectedRole) {
                        ForEach(VineyardRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
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
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Invite Member")
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

        isSending = true
        Task {
            let success = await authService.inviteMember(
                email: trimmed,
                role: selectedRole,
                vineyardId: vineyard.id,
                vineyardName: vineyard.name
            )
            isSending = false
            if success {
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
                                Task { await authService.acceptInvitation(invitation) }
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
