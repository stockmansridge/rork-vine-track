import SwiftUI

struct PasswordResetCodeView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var code: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var localError: String?
    @State private var isPasswordVisible: Bool = false
    @FocusState private var focused: Field?

    private enum Field { case email, code, password, confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)

                    TextField("Verification code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($focused, equals: .code)
                        .onChange(of: code) { _, newValue in
                            let digits = newValue.filter { $0.isNumber }
                            if digits != newValue { code = digits }
                            if digits.count > 10 { code = String(digits.prefix(10)) }
                        }
                } header: {
                    Text("Verification")
                } footer: {
                    Text("Enter the code from the Supabase password reset email. If you don't see it, check spam.")
                }

                Section {
                    HStack {
                        Group {
                            if isPasswordVisible {
                                TextField("New password", text: $newPassword)
                            } else {
                                SecureField("New password", text: $newPassword)
                            }
                        }
                        .textContentType(.newPassword)
                        .focused($focused, equals: .password)

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirm)
                } header: {
                    Text("New password")
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
                            if authService.isVerifyingResetCode {
                                ProgressView()
                            }
                            Text("Reset password")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(authService.isVerifyingResetCode || !canSubmit)

                    Button {
                        Task { await resend() }
                    } label: {
                        HStack {
                            if authService.isSendingPasswordReset {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Resend code")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(authService.isSendingPasswordReset || email.isEmpty)
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if email.isEmpty {
                    email = authService.passwordResetPendingEmail
                }
                focused = .code
            }
            .interactiveDismissDisabled(authService.isVerifyingResetCode)
        }
    }

    private var canSubmit: Bool {
        !email.isEmpty && code.count >= 6 && !newPassword.isEmpty && !confirmPassword.isEmpty
    }

    private func submit() async {
        localError = nil
        authService.errorMessage = nil
        guard newPassword == confirmPassword else {
            localError = "Passwords don't match."
            return
        }
        let ok = await authService.verifyResetCodeAndUpdatePassword(
            email: email,
            code: code,
            newPassword: newPassword
        )
        if ok { dismiss() }
    }

    private func resend() async {
        localError = nil
        authService.errorMessage = nil
        authService.sendPasswordReset(email: email)
    }
}
