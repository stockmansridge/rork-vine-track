import SwiftUI
import GoogleSignInSwift
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var name: String = ""
    @State private var isSignUp: Bool = false
    @State private var isPasswordVisible: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, email, password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                VStack(spacing: 20) {
                    if let uiImage = UIImage(named: "AppIcon") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .clipShape(.rect(cornerRadius: 22))
                    }

                    VStack(spacing: 6) {
                        Text("VineTrack")
                            .font(.largeTitle.weight(.bold))

                        Text("Vineyard Management")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                    .frame(height: 40)

                VStack(spacing: 14) {
                    if isSignUp {
                        HStack(spacing: 10) {
                            Image(systemName: "person")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            TextField("Full Name", text: $name)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: 12))
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 12))

                    HStack(spacing: 10) {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Group {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(isSignUp ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 12))

                    Button {
                        focusedField = nil
                        if isSignUp {
                            authService.signUpWithEmail(name: name, email: email, password: password)
                        } else {
                            authService.signInWithEmail(email: email, password: password)
                        }
                    } label: {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VineyardTheme.olive)
                    .clipShape(.rect(cornerRadius: 12))

                    if !isSignUp {
                        HStack {
                            Spacer()
                            Button {
                                focusedField = nil
                                authService.sendPasswordReset(email: email)
                            } label: {
                                if authService.isSendingPasswordReset {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Forgot password?")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(VineyardTheme.olive)
                                }
                            }
                            .disabled(authService.isSendingPasswordReset)
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSignUp.toggle()
                            authService.errorMessage = nil
                            authService.showEmailConfirmation = false
                        }
                    } label: {
                        Text(isSignUp ? "Already have an account? **Sign In**" : "Don't have an account? **Sign Up**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 28)

                dividerRow

                Spacer()
                    .frame(height: 20)

                VStack(spacing: 12) {
                    Button {
                        authService.signInWithApple()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .font(.body.weight(.medium))
                                .frame(width: 20)
                            Text("Sign in with Apple")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(.black)
                        .clipShape(.rect(cornerRadius: 12))
                    }

                    Button {
                        authService.signInWithGoogle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                                .font(.body.weight(.medium))
                                .frame(width: 20)
                            Text("Sign in with Google")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.primary)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 32)

                if authService.showEmailConfirmation {
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.badge")
                            .font(.title2)
                            .foregroundStyle(VineyardTheme.olive)
                        Text("Check your email")
                            .font(.subheadline.weight(.semibold))
                        Text("We sent a confirmation link to **\(email)**. Please verify your email, then sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.top, 12)
                    .padding(.horizontal, 32)
                }

                if let resetMessage = authService.passwordResetMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(VineyardTheme.olive)
                        Text(resetMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.top, 12)
                    .padding(.horizontal, 32)
                }

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.horizontal, 32)
                }

                Spacer()
                    .frame(height: 20)

                Button {
                    authService.enterDemoMode()
                } label: {
                    Text("Continue in Demo Mode")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: Bindable(authService).showPasswordResetCodeEntry) {
            PasswordResetCodeView()
        }
        .onSubmit {
            switch focusedField {
            case .name:
                focusedField = .email
            case .email:
                focusedField = .password
            case .password:
                if isSignUp {
                    authService.signUpWithEmail(name: name, email: email, password: password)
                } else {
                    authService.signInWithEmail(email: email, password: password)
                }
                focusedField = nil
            case nil:
                break
            }
        }
    }

    private var dividerRow: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
        .padding(.horizontal, 32)
    }
}
