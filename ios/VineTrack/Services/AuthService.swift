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
    var isAuthenticating: Bool = false
    var showEmailConfirmation: Bool = false
    var isOfflineSession: Bool = false
    var passwordResetMessage: String?
    var isSendingPasswordReset: Bool = false
    var showPasswordRecovery: Bool = false
    var isUpdatingPassword: Bool = false
    var showPasswordResetCodeEntry: Bool = false
    var passwordResetPendingEmail: String = ""
    var isVerifyingResetCode: Bool = false

    static let passwordResetRedirectURL = URL(string: "vinetrack://auth-callback")!
    static let emailConfirmRedirectURL = URL(string: "vinetrack://auth-callback")!

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
            applySession(session)
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

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )
            userId = session.user.id.uuidString.lowercased()
            updateGoogleUser(user)
            isSignedIn = true
            persistUserLocally()
            await createProfileIfNeeded()
        } catch {
            errorMessage = userFriendlyAuthError(error, provider: "Google")
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
            if result.session != nil {
                userId = result.user.id.uuidString.lowercased()
                userName = name
                userEmail = email
                isSignedIn = true
                persistUserLocally()
                await createProfileIfNeeded()
            } else {
                showEmailConfirmation = true
            }
        } catch {
            errorMessage = error.localizedDescription
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
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            userId = session.user.id.uuidString.lowercased()
            userEmail = email
            userName = session.user.userMetadata["full_name"]?.value as? String ?? email
            isSignedIn = true
            persistUserLocally()
        } catch {
            errorMessage = userFriendlyAuthError(error, provider: "email")
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
        print("[AuthService] resetPasswordForEmail (code flow) for: \(trimmedEmail)")
        Task {
            do {
                try await supabase.auth.resetPasswordForEmail(trimmedEmail)
                passwordResetPendingEmail = trimmedEmail
                showPasswordResetCodeEntry = true
                passwordResetMessage = "We sent a 6-digit code to \(trimmedEmail). Enter it below to reset your password."
            } catch {
                errorMessage = "Couldn't send reset email: \(error.localizedDescription)"
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

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: nonce
                )
            )
            userId = session.user.id.uuidString.lowercased()
            userEmail = session.user.email ?? credential.email ?? ""

            if let fullName = credential.fullName {
                let name = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !name.isEmpty {
                    userName = name
                }
            }
            if userName.isEmpty {
                userName = session.user.userMetadata["full_name"]?.value as? String ?? ""
            }

            isSignedIn = true
            persistUserLocally()
            await createProfileIfNeeded()
        } catch {
            errorMessage = userFriendlyAuthError(error, provider: "Apple")
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

        // Primary path: SECURITY DEFINER RPC that resolves the current
        // user's email from auth.users (not the JWT email claim, which is
        // sometimes missing for Google / Apple OIDC sign-ins on a fresh
        // device). This bypasses RLS and reliably returns every pending
        // invitation addressed to this user, even when the direct
        // .from("invitations").select() below would return 0 rows.
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
                .eq("id", value: invitation.id.uuidString)
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
                .eq("id", value: invitation.id.uuidString)
                .execute()
            try? await supabase.from("invitations")
                .delete()
                .eq("id", value: invitation.id.uuidString)
                .execute()
            sentInvitations.removeAll { $0.id == invitation.id }
            return true
        } catch {
            errorMessage = "Failed to cancel invitation: \(error.localizedDescription)"
            return false
        }
    }

    func acceptInvitation(_ invitation: TeamInvitation) async {
        guard isSupabaseConfigured, let uid = userId else {
            errorMessage = "You must be signed in to accept invitations."
            return
        }
        let lowerUid = uid.lowercased()
        var rpcError: Error?

        // Primary path: SECURITY DEFINER RPC - bypasses RLS, normalizes
        // the uuid casing, and inserts into vineyard_members atomically.
        // The SQL function (FINAL_FIX_INVITE_CASE.sql) accepts either a
        // token or the invitation id as p_token.
        nonisolated struct AcceptParams: Codable, Sendable {
            let p_token: String
        }
        let params = AcceptParams(p_token: invitation.id.uuidString.lowercased())
        do {
            try await supabase.rpc("accept_invitation", params: params).execute()
            pendingInvitations.removeAll { $0.id == invitation.id }
            print("[AuthService] accept_invitation RPC succeeded for \(invitation.id.uuidString)")
            return
        } catch {
            rpcError = error
            print("[AuthService] accept_invitation RPC failed, trying bulk RPC: \(error)")
        }

        // Secondary path: bulk RPC that matches by email from auth.users,
        // tolerant to any JWT-email claim issues. Only treat it as success
        // if membership actually exists afterwards, so we don't silently
        // swallow the original error when the RPC did nothing.
        do {
            try await supabase.rpc("accept_pending_invitations_for_me").execute()
            let memberships: [VineyardMemberRecord] = (try? await supabase.from("vineyard_members")
                .select()
                .eq("vineyard_id", value: invitation.vineyard_id)
                .eq("user_id", value: lowerUid)
                .execute()
                .value) ?? []
            if !memberships.isEmpty {
                pendingInvitations.removeAll { $0.id == invitation.id }
                print("[AuthService] accept_pending_invitations_for_me RPC succeeded and membership confirmed")
                return
            }
            print("[AuthService] bulk RPC ran but no membership row found - trying direct insert")
        } catch {
            print("[AuthService] accept_pending_invitations_for_me RPC failed, falling back to direct insert: \(error)")
        }

        // Fallback: direct upsert. Uses the LOWERCASE uid so the RLS
        // insert policy (auth.uid()::text = user_id) actually matches.
        do {
            let memberRecord = VineyardMemberRecord(
                id: nil,
                vineyard_id: invitation.vineyard_id,
                user_id: lowerUid,
                name: userName.isEmpty ? userEmail : userName,
                role: invitation.role,
                joined_at: nil
            )
            try await supabase.from("vineyard_members")
                .upsert(memberRecord, onConflict: "vineyard_id,user_id")
                .execute()

            nonisolated struct StatusUpdate: Codable, Sendable {
                let status: String
            }
            try await supabase.from("invitations")
                .update(StatusUpdate(status: "accepted"))
                .eq("id", value: invitation.id.uuidString)
                .execute()

            pendingInvitations.removeAll { $0.id == invitation.id }
            print("[AuthService] accept_invitation fallback insert succeeded for \(invitation.id.uuidString)")
        } catch {
            print("[AuthService] accept_invitation fallback insert failed: \(error)")
            let rpcDesc = rpcError.map { $0.localizedDescription } ?? "n/a"
            errorMessage = "Failed to accept invitation.\nRPC: \(rpcDesc)\nInsert: \(error.localizedDescription)"
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
                .eq("id", value: invitation.id.uuidString)
                .execute()

            pendingInvitations.removeAll { $0.id == invitation.id }
        } catch {
            errorMessage = "Failed to decline invitation: \(error.localizedDescription)"
        }
    }

    func inviteMember(email: String, role: VineyardRole, vineyardId: UUID, vineyardName: String) async -> Bool {
        guard isSupabaseConfigured, let uid = userId else {
            errorMessage = "You must be signed in to send invitations."
            return false
        }
        let lowered = email.lowercased()
        print("[AuthService] inviteMember email=\(lowered) vineyard=\(vineyardId.uuidString) role=\(role.rawValue)")

        nonisolated struct CreateInvitationParams: Codable, Sendable {
            let p_vineyard_id: String
            let p_vineyard_name: String
            let p_email: String
            let p_role: String
            let p_invited_by_name: String
        }
        let params = CreateInvitationParams(
            p_vineyard_id: vineyardId.uuidString.lowercased(),
            p_vineyard_name: vineyardName,
            p_email: lowered,
            p_role: role.rawValue,
            p_invited_by_name: userName
        )

        var rpcError: Error?
        do {
            try await supabase.rpc("create_invitation", params: params).execute()
            print("[AuthService] create_invitation RPC succeeded")
        } catch {
            rpcError = error
            print("[AuthService] create_invitation RPC failed: \(error)")
        }

        if rpcError != nil {
            // Fallback: direct insert (requires invitations RLS insert policy to be in place)
            do {
                nonisolated struct InsertRow: Codable, Sendable {
                    let vineyard_id: String
                    let vineyard_name: String
                    let email: String
                    let role: String
                    let invited_by: String
                    let invited_by_name: String
                    let status: String
                }
                let row = InsertRow(
                    vineyard_id: vineyardId.uuidString.lowercased(),
                    vineyard_name: vineyardName,
                    email: lowered,
                    role: role.rawValue,
                    invited_by: uid,
                    invited_by_name: userName,
                    status: "pending"
                )
                try await supabase.from("invitations").insert(row).execute()
                print("[AuthService] direct insert fallback succeeded")
            } catch {
                print("[AuthService] direct insert fallback failed: \(error)")
                let rpcDesc = rpcError.map { "\($0)" } ?? "nil"
                errorMessage = "Failed to save invitation.\nRPC error: \(rpcDesc)\nInsert error: \(error.localizedDescription)\nRun sql/fix_create_invitation_owner.sql in Supabase SQL Editor."
                return false
            }
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

    private func userFriendlyAuthError(_ error: Error, provider: String) -> String {
        let rawMessage = String(describing: error)
        let localized = error.localizedDescription
        let combined = "\(localized) \(rawMessage)".lowercased()

        if combined.contains("invalid login credentials") || combined.contains("invalid_credentials") {
            return "Supabase rejected the email/password for this account. Use Forgot password to reset it, or sign in with the provider originally used for this account."
        }

        if combined.contains("provider") && combined.contains("not enabled") || combined.contains("provider_disabled") {
            return "\(provider) sign-in is currently disabled in Supabase Auth for this backend. Use email/password or Apple sign-in until the provider is re-enabled."
        }

        if combined.contains("email not confirmed") || combined.contains("email_not_confirmed") {
            return "Please confirm your email address before signing in."
        }

        return "\(provider) sign-in failed: \(localized)"
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
                    self.applySession(session)
                }

                self.passwordResetMessage = nil
                self.showEmailConfirmation = false
                self.showPasswordRecovery = true
                self.errorMessage = nil
            }
        }
    }

    private func applySession(_ session: Session) {
        let user = session.user
        userId = user.id.uuidString.lowercased()
        userEmail = user.email ?? userEmail

        if let fullName = user.userMetadata["full_name"]?.value as? String,
           !fullName.isEmpty {
            userName = fullName
        } else if userName.isEmpty {
            userName = UserDefaults.standard.string(forKey: userNameKey) ?? ""
        }

        isSignedIn = true
        isOfflineSession = false
        persistUserLocally()
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
