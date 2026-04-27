import Foundation
import GoogleSignIn
import Supabase
import Auth
import AuthenticationServices
import CryptoKit

@Observable
@MainActor
class AuthService {
    var isSignedIn: Bool = false
    var isLoading: Bool = true
    var userName: String = ""
    var userEmail: String = ""
    var userProfileURL: URL?
    var errorMessage: String?
    var userId: String?
    var isDemoMode: Bool = false
    var pendingInvitations: [TeamInvitation] = []
    var sentInvitations: [TeamInvitation] = []
    var isDeletingAccount: Bool = false
    var showEmailConfirmation: Bool = false
    var isOfflineSession: Bool = false
    var passwordResetMessage: String?
    var isSendingPasswordReset: Bool = false
    var showPasswordRecovery: Bool = false
    var isUpdatingPassword: Bool = false
    var showPasswordResetCodeEntry: Bool = false
    var passwordResetPendingEmail: String = ""
    var isVerifyingResetCode: Bool = false

    /// Single source of truth for the signed-in user's vineyard access.
    /// Populated after every successful authentication and after invitation
    /// changes. Per-vineyard membership and role are derived from this.
    var accessSnapshot: VineyardAccessPayload?

    static let passwordResetRedirectURL = URL(string: "vinetrack://reset-password?flow=recovery")!
    static let emailConfirmRedirectURL = URL(string: "vinetrack://auth-callback?flow=signup")!

    private var authStateChangesTask: Task<Void, Never>?

    private let signedInKey = "vinetrack_signed_in"
    private let userNameKey = "vinetrack_user_name"
    private let userEmailKey = "vinetrack_user_email"
    private let userIdKey = "vinetrack_user_id"
    private let lastAuthAtKey = "vinetrack_last_auth_at"

    static let offlineGracePeriod: TimeInterval = 7 * 24 * 60 * 60

    private var currentNonce: String?

    private var googleClientID: String {
        Config.EXPO_PUBLIC_GOOGLE_CLIENT_ID
    }

    private var isGoogleConfigured: Bool {
        !googleClientID.isEmpty
    }

    init() {
        userName = UserDefaults.standard.string(forKey: userNameKey) ?? ""
        userEmail = UserDefaults.standard.string(forKey: userEmailKey) ?? ""
        userId = UserDefaults.standard.string(forKey: userIdKey)
        configureGoogleSignIn()
        startAuthStateListener()
    }

    private func configureGoogleSignIn() {
        guard isGoogleConfigured else { return }
        if GIDSignIn.sharedInstance.configuration == nil {
            let config = GIDConfiguration(clientID: googleClientID)
            GIDSignIn.sharedInstance.configuration = config
        }
    }

    func restorePreviousSignIn() {
        Task {
            await restoreSupabaseSession()
        }
    }

    private func restoreSupabaseSession() async {
        guard isSupabaseConfigured else {
            isSignedIn = false
            isLoading = false
            return
        }
        do {
            let session = try await supabase.auth.session
            await completeSignedInSession(session)
            isLoading = false
        } catch {
            if tryRestoreOfflineSession() {
                isLoading = false
                return
            }
            isSignedIn = false
            isOfflineSession = false
            UserDefaults.standard.set(false, forKey: signedInKey)
            isLoading = false
        }
    }

    private func tryRestoreOfflineSession() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: signedInKey) else { return false }
        let lastAuthAt = defaults.double(forKey: lastAuthAtKey)
        guard lastAuthAt > 0 else { return false }
        let elapsed = Date().timeIntervalSince1970 - lastAuthAt
        guard elapsed >= 0, elapsed <= Self.offlineGracePeriod else { return false }
        guard let cachedId = defaults.string(forKey: userIdKey), !cachedId.isEmpty else { return false }

        userId = cachedId
        userName = defaults.string(forKey: userNameKey) ?? ""
        userEmail = defaults.string(forKey: userEmailKey) ?? ""
        isSignedIn = true
        isOfflineSession = true
        return true
    }

    func signInWithGoogle() {
        guard isGoogleConfigured else {
            errorMessage = "Google Sign-In is not configured"
            return
        }
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured. Please try again later."
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller"
            return
        }

        errorMessage = nil
        clearDemoSessionIfNeeded()

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let user = result?.user else { return }
                await self.signInGoogleWithSupabase(user: user)
            }
        }
    }

    private func signInGoogleWithSupabase(user: GIDGoogleUser) async {
        guard let idToken = user.idToken?.tokenString else {
            errorMessage = "Failed to get Google ID token"
            return
        }
        let accessToken = user.accessToken.tokenString

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )
            await completeSignedInSession(
                session,
                preferredEmail: user.profile?.email,
                preferredName: user.profile?.name
            )
            userProfileURL = user.profile?.imageURL(withDimension: 120)
        } catch {
            errorMessage = "Google sign-in failed: \(error.localizedDescription)"
        }
    }

    func signUpWithEmail(name: String, email: String, password: String) {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !password.isEmpty, !trimmedName.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            errorMessage = "Please enter a valid email address"
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured. Please try again later."
            return
        }

        clearDemoSessionIfNeeded()
        Task {
            await supabaseSignUp(name: trimmedName, email: trimmedEmail, password: password)
        }
    }

    private func supabaseSignUp(name: String, email: String, password: String) async {
        do {
            let result = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(name)],
                redirectTo: Self.emailConfirmRedirectURL
            )
            if let session = result.session {
                await completeSignedInSession(session, preferredEmail: email, preferredName: name)
            } else {
                showEmailConfirmation = true
            }
        } catch {
            print("[AuthService] Email sign-up failed for \(email): \(error)")
            errorMessage = authErrorMessage(for: error, fallback: "Couldn't create account")
        }
    }

    func signInWithEmail(email: String, password: String) {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password"
            return
        }
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured. Please try again later."
            return
        }

        clearDemoSessionIfNeeded()
        Task {
            await supabaseSignIn(email: trimmedEmail, password: password)
        }
    }

    private func supabaseSignIn(email: String, password: String) async {
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            let metadataName = session.user.userMetadata["full_name"]?.value as? String
            await completeSignedInSession(
                session,
                preferredEmail: email,
                preferredName: metadataName ?? email
            )
        } catch {
            print("[AuthService] Email sign-in failed for \(email): \(error)")
            errorMessage = signInErrorMessage(for: error)
        }
    }

    func sendPasswordReset(email: String) {
        errorMessage = nil
        passwordResetMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email address first"
            return
        }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Please enter a valid email address"
            return
        }
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured. Please try again later."
            return
        }

        isSendingPasswordReset = true
        print("[AuthService] Requesting password reset code for: \(trimmedEmail)")
        Task {
            do {
                try await supabase.auth.resetPasswordForEmail(trimmedEmail)
                passwordResetPendingEmail = trimmedEmail
                showPasswordResetCodeEntry = true
                passwordResetMessage = "Enter the code sent to \(trimmedEmail) to set a new password."
            } catch {
                print("[AuthService] password reset request failed for \(trimmedEmail): \(error)")
                errorMessage = "Couldn't send reset code: \(authErrorMessage(for: error, fallback: "Password reset failed"))"
            }
            isSendingPasswordReset = false
        }
    }

    func verifyResetCodeAndUpdatePassword(email: String, code: String, newPassword: String) async -> Bool {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email."
            return false
        }
        guard !trimmedCode.isEmpty else {
            errorMessage = "Please enter the code from your email."
            return false
        }
        guard trimmedPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return false
        }
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured."
            return false
        }

        isVerifyingResetCode = true
        defer { isVerifyingResetCode = false }

        do {
            _ = try await supabase.auth.verifyOTP(email: trimmedEmail, token: trimmedCode, type: .recovery)
        } catch {
            print("[AuthService] verifyOTP(.recovery) failed for \(trimmedEmail): \(error)")
            errorMessage = "Invalid or expired code. Please request a new one."
            return false
        }

        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: trimmedPassword))
            passwordResetMessage = "Password updated. You're signed in."
            showPasswordResetCodeEntry = false
            passwordResetPendingEmail = ""
            await restoreSupabaseSession()
            return true
        } catch {
            errorMessage = "Couldn't update password: \(error.localizedDescription)"
            return false
        }
    }

    private func clearDemoSessionIfNeeded() {
        guard isDemoMode else { return }
        isDemoMode = false
        isSignedIn = false
        userName = ""
        userEmail = ""
        userProfileURL = nil
        userId = nil
        pendingInvitations = []
        sentInvitations = []
    }

    func enterDemoMode() {
        isDemoMode = true
        isSignedIn = true
        userName = "Demo User"
        userEmail = "demo@vinetrack.app"
        userId = "demo-user-\(UUID().uuidString)"
        isLoading = false
    }

    func signOut() {
        if isDemoMode {
            isDemoMode = false
            isSignedIn = false
            userName = ""
            userEmail = ""
            userProfileURL = nil
            userId = nil
            pendingInvitations = []
            sentInvitations = []
            errorMessage = nil
            return
        }
        Task {
            try? await supabase.auth.signOut()
        }
        if isGoogleConfigured {
            GIDSignIn.sharedInstance.signOut()
        }
        isSignedIn = false
        isOfflineSession = false
        userName = ""
        userEmail = ""
        userProfileURL = nil
        userId = nil
        pendingInvitations = []
        sentInvitations = []
        accessSnapshot = nil
        errorMessage = nil
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: signedInKey)
        defaults.removeObject(forKey: userNameKey)
        defaults.removeObject(forKey: userEmailKey)
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: lastAuthAtKey)
    }

    func deleteAccount(dataStore: DataStore) async {
        guard isSupabaseConfigured, let uid = userId else {
            dataStore.deleteAllData()
            signOut()
            return
        }

        isDeletingAccount = true
        errorMessage = nil

        do {
            let ownedVineyards: [VineyardRecord] = try await supabase.from("vineyards")
                .select()
                .eq("owner_id", value: uid)
                .execute()
                .value

            let ownedIds = ownedVineyards.map { $0.id }

            for vineyardId in ownedIds {
                try await supabase.from("vineyard_data")
                    .delete()
                    .eq("vineyard_id", value: vineyardId)
                    .execute()

                try await supabase.from("invitations")
                    .delete()
                    .eq("vineyard_id", value: vineyardId)
                    .execute()

                try await supabase.from("vineyard_members")
                    .delete()
                    .eq("vineyard_id", value: vineyardId)
                    .execute()
            }

            try await supabase.from("vineyards")
                .delete()
                .eq("owner_id", value: uid)
                .execute()

            try await supabase.from("vineyard_members")
                .delete()
                .eq("user_id", value: uid)
                .execute()

            try? await supabase.from("analytics_events")
                .delete()
                .eq("user_id", value: uid)
                .execute()

            try? await supabase.from("support_requests")
                .delete()
                .eq("user_id", value: uid)
                .execute()

            try? await supabase.from("disclaimer_acceptances")
                .delete()
                .eq("user_id", value: uid)
                .execute()

            try await supabase.from("profiles")
                .delete()
                .eq("id", value: uid)
                .execute()

            try? await supabase.rpc("delete_user_account").execute()
        } catch {
            print("Account deletion error: \(error)")
        }

        dataStore.deleteAllData()
        isDeletingAccount = false
        signOut()
    }

    func signInWithApple() {
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured. Please try again later."
            return
        }
        clearDemoSessionIfNeeded()
        let nonce = randomNonceString()
        currentNonce = nonce
        let hashedNonce = sha256(nonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleSignInDelegate { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let authorization):
                    await self.handleAppleAuthorization(authorization)
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code == .canceled { return }
                    self.errorMessage = "Apple sign-in failed: \(error.localizedDescription)"
                }
            }
        }
        controller.delegate = delegate
        self._appleSignInDelegate = delegate

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let contextProvider = AppleSignInPresentationContext(window: window)
            controller.presentationContextProvider = contextProvider
            self._appleContextProvider = contextProvider
        }

        controller.performRequests()
    }

    private var _appleSignInDelegate: AppleSignInDelegate?
    private var _appleContextProvider: AppleSignInPresentationContext?

    private func handleAppleAuthorization(_ authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let nonce = currentNonce else {
            errorMessage = "Failed to get Apple ID credentials"
            return
        }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: nonce
                )
            )
            let appleName: String? = {
                guard let fullName = credential.fullName else { return nil }
                let name = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                return name.isEmpty ? nil : name
            }()
            let metadataName = session.user.userMetadata["full_name"]?.value as? String
            await completeSignedInSession(
                session,
                preferredEmail: session.user.email ?? credential.email,
                preferredName: appleName ?? metadataName
            )
        } catch {
            errorMessage = "Apple sign-in failed: \(error.localizedDescription)"
        }

        currentNonce = nil
        _appleSignInDelegate = nil
        _appleContextProvider = nil
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess { fatalError("Unable to generate nonce") }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    func handleURL(_ url: URL) -> Bool {
        print("[AuthService] handleURL received: \(url.absoluteString)")
        if url.scheme?.lowercased() == "vinetrack" {
            let host = url.host?.lowercased() ?? ""
            print("[AuthService] custom scheme host: \(host)")
            Task { await handleSupabaseCallbackURL(url) }
            return true
        }
        guard isGoogleConfigured else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    private func handleSupabaseCallbackURL(_ url: URL) async {
        print("[AuthService] handleSupabaseCallbackURL: \(url.absoluteString)")
        guard isSupabaseConfigured else {
            print("[AuthService] Supabase not configured; ignoring callback URL")
            return
        }
        let isPasswordRecovery = isPasswordRecoveryCallback(url)
        print("[AuthService] isPasswordRecovery: \(isPasswordRecovery)")

        do {
            try await establishSupabaseSession(from: url)
            await restoreSupabaseSession()
            showEmailConfirmation = false
            errorMessage = nil

            if isPasswordRecovery {
                passwordResetMessage = nil
                showPasswordRecovery = true
                print("[AuthService] Password recovery session established")
            }
        } catch {
            print("[AuthService] Callback failed: \(error)")
            if isPasswordRecovery {
                showPasswordRecovery = false
                errorMessage = "Password reset link is invalid or expired: \(error.localizedDescription)"
            } else {
                errorMessage = "Confirmation link is invalid or expired: \(error.localizedDescription)"
            }
        }
    }

    private func establishSupabaseSession(from url: URL) async throws {
        if let authCode = authCode(from: url) {
            print("[AuthService] Exchanging auth code for session")
            _ = try await supabase.auth.exchangeCodeForSession(authCode: authCode)
            return
        }

        if let accessToken = parameter(named: "access_token", in: url),
           let refreshToken = parameter(named: "refresh_token", in: url) {
            print("[AuthService] Setting session from access/refresh tokens in URL")
            _ = try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
            return
        }

        if let tokenHash = parameter(named: "token_hash", in: url) ?? parameter(named: "token", in: url) {
            let typeString = parameter(named: "type", in: url)?.lowercased() ?? "recovery"
            let otpType: EmailOTPType = {
                switch typeString {
                case "signup": return .signup
                case "invite": return .invite
                case "magiclink": return .magiclink
                case "email_change": return .emailChange
                case "email": return .email
                default: return .recovery
                }
            }()
            print("[AuthService] Verifying OTP token_hash with type: \(typeString)")
            _ = try await supabase.auth.verifyOTP(tokenHash: tokenHash, type: otpType)
            return
        }

        print("[AuthService] Falling back to session(from:) parsing")
        try await supabase.auth.session(from: url)
    }

    private func authCode(from url: URL) -> String? {
        parameter(named: "code", in: url) ?? parameter(named: "auth_code", in: url)
    }

    private func isPasswordRecoveryCallback(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host == "reset-password" {
            return true
        }

        let type = parameter(named: "type", in: url)?.lowercased() ?? ""
        if type == "recovery" {
            return true
        }

        let flow = parameter(named: "flow", in: url)?.lowercased() ?? ""
        return flow == "recovery" || flow == "reset-password"
    }

    private func parameter(named name: String, in url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == name })?.value,
           !value.isEmpty {
            return value
        }

        guard let fragment = url.fragment, !fragment.isEmpty,
              let components = URLComponents(string: "vinetrack://callback?\(fragment)"),
              let value = components.queryItems?.first(where: { $0.name == name })?.value,
              !value.isEmpty else {
            return nil
        }

        return value
    }

    func updatePassword(_ newPassword: String) async -> Bool {
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured."
            return false
        }
        let trimmed = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return false
        }
        isUpdatingPassword = true
        defer { isUpdatingPassword = false }
        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: trimmed))
            passwordResetMessage = "Password updated. You're signed in."
            showPasswordRecovery = false
            await restoreSupabaseSession()
            return true
        } catch {
            errorMessage = "Couldn't update password: \(error.localizedDescription)"
            return false
        }
    }

    func loadPendingInvitations() async {
        let normalizedEmail: String = normalizedEmailAddress(userEmail)
        guard isSupabaseConfigured else {
            pendingInvitations = []
            return
        }

        do {
            let payload = try await VineyardAccessService.fetch()
            accessSnapshot = payload
            pendingInvitations = payload.pendingInvitations
            if errorMessage?.contains("Couldn't load invitations") == true {
                errorMessage = nil
            }
            print("[AuthService] access snapshot returned \(payload.pendingInvitations.count) invitation(s)")
            return
        } catch {
            print("[AuthService] access snapshot invitation lookup failed, falling back: \(error)")
        }

        if let rows: [TeamInvitation] = try? await supabase
            .rpc("get_my_pending_invitations")
            .execute()
            .value {
            pendingInvitations = rows
            if errorMessage?.contains("Couldn't load invitations") == true {
                errorMessage = nil
            }
            print("[AuthService] get_my_pending_invitations RPC returned \(rows.count) invitation(s)")
            return
        } else {
            print("[AuthService] get_my_pending_invitations RPC unavailable, falling back (run sql/get_my_pending_invitations.sql in Supabase)")
        }

        guard !normalizedEmail.isEmpty else {
            pendingInvitations = []
            return
        }

        do {
            let invitations: [TeamInvitation] = try await supabase.from("invitations")
                .select()
                .eq("status", value: "pending")
                .ilike("email", pattern: "%\(normalizedEmail)%")
                .order("created_at", ascending: false)
                .execute()
                .value
            pendingInvitations = invitations.filter { normalizedEmailAddress($0.email) == normalizedEmail }
            if errorMessage?.contains("Couldn't load invitations") == true {
                errorMessage = nil
            }
        } catch {
            pendingInvitations = []
            errorMessage = "Couldn't load invitations: \(error.localizedDescription)"
        }
    }

    func loadSentInvitations(vineyardId: UUID) async {
        guard isSupabaseConfigured else { return }

        nonisolated struct ListParams: Codable, Sendable {
            let p_vineyard_id: String
        }
        let params = ListParams(p_vineyard_id: vineyardId.uuidString.lowercased())

        var rpcError: Error?
        do {
            let invitations: [TeamInvitation] = try await supabase
                .rpc("list_invitations_for_vineyard", params: params)
                .execute()
                .value
            sentInvitations = invitations.filter { $0.status.lowercased() != "cancelled" }
            errorMessage = nil
            print("[AuthService] RPC loaded \(invitations.count) invitations for vineyard \(vineyardId.uuidString)")
            return
        } catch {
            rpcError = error
            print("[AuthService] list_invitations_for_vineyard RPC failed, falling back to direct select: \(error)")
        }

        do {
            let invitations: [TeamInvitation] = try await supabase.from("invitations")
                .select()
                .eq("vineyard_id", value: vineyardId.uuidString.lowercased())
                .neq("status", value: "cancelled")
                .order("created_at", ascending: false)
                .execute()
                .value
            sentInvitations = invitations.filter { $0.status.lowercased() != "cancelled" }
            errorMessage = nil
            print("[AuthService] direct-select loaded \(invitations.count) invitations for vineyard \(vineyardId.uuidString)")
        } catch {
            print("[AuthService] Failed to load sent invitations: \(error)")
            let rpcDesc = rpcError.map { String(describing: $0) } ?? "n/a"
            errorMessage = "Couldn't load invitations.\nRPC error: \(rpcDesc)\nSelect error: \(error.localizedDescription)"
        }
    }

    func resendInvitation(_ invitation: TeamInvitation) async -> Bool {
        guard isSupabaseConfigured else { return false }
        do {
            nonisolated struct ResendUpdate: Codable, Sendable {
                let status: String
                let created_at: String
            }
            let iso = ISO8601DateFormatter().string(from: Date())
            let update = ResendUpdate(status: "pending", created_at: iso)
            try await supabase.from("invitations")
                .update(update)
                .eq("id", value: invitation.id.uuidString.lowercased())
                .execute()
            if let idx = sentInvitations.firstIndex(where: { $0.id == invitation.id }) {
                sentInvitations[idx].status = "pending"
                sentInvitations[idx].created_at = iso
            }
            await sendInvitationEmail(
                email: invitation.email,
                vineyardName: invitation.vineyard_name ?? "a vineyard",
                role: invitation.role,
                invitationId: invitation.id.uuidString
            )
            return true
        } catch {
            errorMessage = "Failed to resend invitation: \(error.localizedDescription)"
            return false
        }
    }

    func cancelInvitation(_ invitation: TeamInvitation) async -> Bool {
        guard isSupabaseConfigured else { return false }
        do {
            nonisolated struct StatusUpdate: Codable, Sendable {
                let status: String
            }
            try await supabase.from("invitations")
                .update(StatusUpdate(status: "cancelled"))
                .eq("id", value: invitation.id.uuidString.lowercased())
                .execute()
            try? await supabase.from("invitations")
                .delete()
                .eq("id", value: invitation.id.uuidString.lowercased())
                .execute()
            sentInvitations.removeAll { $0.id == invitation.id }
            return true
        } catch {
            errorMessage = "Failed to cancel invitation: \(error.localizedDescription)"
            return false
        }
    }

    func acceptInvitation(_ invitation: TeamInvitation) async {
        guard isSupabaseConfigured, userId != nil else {
            errorMessage = "You must be signed in to accept invitations."
            return
        }

        // Backend-only flow per Step 7. The app never inserts into
        // vineyard_members directly. The backend resolves the user's
        // email from auth.users and verifies the invitation matches.
        nonisolated struct AcceptParams: Codable, Sendable {
            let p_invitation_id: String
        }
        let params = AcceptParams(p_invitation_id: invitation.id.uuidString.lowercased())

        do {
            try await supabase.rpc("accept_invitation", params: params).execute()
            pendingInvitations.removeAll { $0.id == invitation.id }
            print("[AuthService] accept_invitation succeeded for \(invitation.id.uuidString)")
            // Refresh the access snapshot so the accepted vineyard
            // appears in the selector.
            await loadPendingInvitations()
        } catch {
            print("[AuthService] accept_invitation failed: \(error)")
            errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
        }
    }

    func declineInvitation(_ invitation: TeamInvitation) async {
        guard isSupabaseConfigured else { return }
        do {
            nonisolated struct StatusUpdate: Codable, Sendable {
                let status: String
            }
            try await supabase.from("invitations")
                .update(StatusUpdate(status: "declined"))
                .eq("id", value: invitation.id.uuidString.lowercased())
                .execute()

            pendingInvitations.removeAll { $0.id == invitation.id }
        } catch {
            errorMessage = "Failed to decline invitation: \(error.localizedDescription)"
        }
    }

    func inviteMember(email: String, role: VineyardRole, vineyardId: UUID, vineyardName: String) async -> Bool {
        guard isSupabaseConfigured, userId != nil else {
            errorMessage = "You must be signed in to send invitations."
            return false
        }
        let lowered = normalizedEmailAddress(email)
        print("[AuthService] inviteMember email=\(lowered) vineyard=\(vineyardId.uuidString) role=\(role.rawValue)")

        // Backend-only flow per Step 7. The backend verifies the caller is
        // Owner or Manager for the target vineyard. The app never inserts
        // into invitations directly.
        nonisolated struct CreateInvitationParams: Codable, Sendable {
            let p_vineyard_id: String
            let p_email: String
            let p_role: String
        }
        let params = CreateInvitationParams(
            p_vineyard_id: vineyardId.uuidString.lowercased(),
            p_email: lowered,
            p_role: role.rawValue
        )

        do {
            try await supabase.rpc("create_invitation", params: params).execute()
            print("[AuthService] create_invitation succeeded")
        } catch {
            print("[AuthService] create_invitation failed: \(error)")
            errorMessage = "Failed to send invitation: \(error.localizedDescription)"
            return false
        }

        await sendInvitationEmail(
            email: lowered,
            vineyardName: vineyardName,
            role: role.rawValue,
            invitationId: nil
        )
        await loadSentInvitations(vineyardId: vineyardId)
        return true
    }

    private func sendInvitationEmail(
        email: String,
        vineyardName: String,
        role: String,
        invitationId: String?
    ) async {
        nonisolated struct EmailPayload: Encodable, Sendable {
            let email: String
            let vineyard_name: String
            let role: String
            let invited_by_name: String
            let invitation_id: String?
            let app_store_url: String
        }
        let payload = EmailPayload(
            email: email,
            vineyard_name: vineyardName,
            role: role,
            invited_by_name: userName.isEmpty ? "A VineTrack user" : userName,
            invitation_id: invitationId,
            app_store_url: "https://apps.apple.com/us/app/vineyard-tracker/id6761143377"
        )
        do {
            let urlString = Config.EXPO_PUBLIC_SUPABASE_URL
            let anonKey = Config.EXPO_PUBLIC_SUPABASE_ANON_KEY
            guard let base = URL(string: urlString),
                  let url = URL(string: "/functions/v1/send-invitation-email", relativeTo: base),
                  !anonKey.isEmpty else {
                throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase not configured"])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
            }
            print("[AuthService] send-invitation-email invoked for \(email)")
        } catch {
            print("[AuthService] send-invitation-email failed: \(error)")
            errorMessage = "Invitation saved, but email could not be sent: \(error.localizedDescription)"
        }
    }

    private func createProfileIfNeeded() async {
        guard let uid = userId else { return }
        nonisolated struct ProfileRecord: Codable, Sendable {
            let id: String
            let name: String
            let email: String
        }
        let profile = ProfileRecord(id: uid, name: userName, email: userEmail)
        do {
            try await supabase.from("profiles")
                .upsert(profile)
                .execute()
        } catch {
            print("Failed to create profile: \(error)")
        }
    }

    private func normalizedEmailAddress(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func signInErrorMessage(for error: Error) -> String {
        let rawMessage = "\(error)"
        let localizedMessage = error.localizedDescription
        let combinedMessage = "\(localizedMessage) \(rawMessage)"

        if combinedMessage.localizedCaseInsensitiveContains("Invalid login credentials") || combinedMessage.localizedCaseInsensitiveContains("invalid_credentials") {
            return "Incorrect email or password. Use Forgot password to send a passcode, then set a new password."
        }

        if combinedMessage.localizedCaseInsensitiveContains("Email not confirmed") || combinedMessage.localizedCaseInsensitiveContains("email_not_confirmed") {
            return "Please confirm your email address before signing in. Check your inbox for the confirmation email."
        }

        return authErrorMessage(for: error, fallback: "Sign in failed")
    }

    private func authErrorMessage(for error: Error, fallback: String) -> String {
        let localizedMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localizedMessage.isEmpty {
            return localizedMessage
        }

        let rawMessage = "\(error)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawMessage.isEmpty {
            return rawMessage
        }

        return fallback
    }

    private func startAuthStateListener() {
        guard isSupabaseConfigured else { return }

        authStateChangesTask?.cancel()
        authStateChangesTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await state in supabase.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                guard state.event == .passwordRecovery else { continue }

                if let session = state.session {
                    await self.completeSignedInSession(session)
                }

                self.passwordResetMessage = nil
                self.showEmailConfirmation = false
                self.showPasswordRecovery = true
                self.errorMessage = nil
            }
        }
    }

    private func completeSignedInSession(_ session: Session, preferredEmail: String? = nil, preferredName: String? = nil) async {
        let user = session.user
        userId = user.id.uuidString.lowercased()
        userEmail = normalizedEmailAddress(preferredEmail ?? user.email ?? userEmail)

        let metadataName = user.userMetadata["full_name"]?.value as? String
        let resolvedName = preferredName ?? metadataName ?? userName
        if !resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userName = resolvedName
        } else if userName.isEmpty {
            userName = UserDefaults.standard.string(forKey: userNameKey) ?? userEmail
        }

        isOfflineSession = false
        await createProfileIfNeeded()
        do {
            let payload = try await VineyardAccessService.fetch()
            accessSnapshot = payload
            pendingInvitations = payload.pendingInvitations
            if errorMessage?.contains("Couldn't load invitations") == true {
                errorMessage = nil
            }
        } catch {
            print("[AuthService] access snapshot after sign-in failed: \(error)")
        }
        isSignedIn = true
        persistUserLocally()
    }

    /// Returns the membership row for the given vineyard from the
    /// authoritative access snapshot. The snapshot is the single source
    /// of truth — a user's role is per-vineyard, not global.
    func membership(forVineyardId vineyardId: UUID) -> VineyardAccessMemberRecord? {
        guard let snapshot = accessSnapshot, let uid = userId else { return nil }
        let vid = vineyardId.uuidString.lowercased()
        let normalizedUid = uid.lowercased()
        return snapshot.memberships.first { row in
            row.vineyard_id.lowercased() == vid && row.user_id.lowercased() == normalizedUid
        }
    }

    /// Returns the role for the given vineyard from the access snapshot,
    /// falling back to vineyard ownership. Returns nil if no membership
    /// or ownership relationship exists.
    func role(forVineyardId vineyardId: UUID, ownerId: UUID? = nil) -> VineyardRole? {
        if let row = membership(forVineyardId: vineyardId) {
            return VineyardRole(rawValue: row.role) ?? .operator_
        }
        if let ownerId, let uid = userId, let userUUID = UUID(uuidString: uid), userUUID == ownerId {
            return .owner
        }
        return nil
    }

    private func persistUserLocally() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: signedInKey)
        defaults.set(userName, forKey: userNameKey)
        defaults.set(userEmail, forKey: userEmailKey)
        if let userId {
            defaults.set(userId, forKey: userIdKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: lastAuthAtKey)
    }

    private func updateGoogleUser(_ user: GIDGoogleUser) {
        userName = user.profile?.name ?? ""
        userEmail = user.profile?.email ?? ""
        userProfileURL = user.profile?.imageURL(withDimension: 120)
        persistUserLocally()
    }
}
