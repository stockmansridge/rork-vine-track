import SwiftUI

struct PasswordRecoveryView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var localError: String?
    @FocusState private var focused: Field?

    private enum Field { case new, confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .new)
                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirm)
                } header: {
                    Text("Set a new password")
                } footer: {
                    Text("Must be at least 6 characters.")
                }

                if let message = localError ?? authService.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if authService.isUpdatingPassword {
                                ProgressView()
                            }
                            Text("Update password")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(authService.isUpdatingPassword || newPassword.isEmpty || confirmPassword.isEmpty)
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = .new }
        }
        .interactiveDismissDisabled(authService.isUpdatingPassword)
    }

    private func submit() async {
        localError = nil
        guard newPassword == confirmPassword else {
            localError = "Passwords don't match."
            return
        }
        let ok = await authService.updatePassword(newPassword)
        if ok { dismiss() }
    }
}
