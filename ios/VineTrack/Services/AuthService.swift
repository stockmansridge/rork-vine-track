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

    private let signedInKey = "vinetrack_signed_in"
    private let userNameKey = "vinetrack_user_name"
    private let userEmailKey = "vinetrack_user_email"

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
        configureGoogleSignIn()
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
            let user = session.user
            userId = user.id.uuidString
            userEmail = user.email ?? ""
            userName = user.userMetadata["full_name"]?.value as? String ?? UserDefaults.standard.string(forKey: userNameKey) ?? ""
            isSignedIn = true
            persistUserLocally()
            isLoading = false
        } catch {
            isSignedIn = false
            UserDefaults.standard.set(false, forKey: signedInKey)
            isLoading = false
        }
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
            userId = session.user.id.uuidString
            updateGoogleUser(user)
            isSignedIn = true
            persistUserLocally()
            await createProfileIfNeeded()
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

        Task {
            await supabaseSignUp(name: trimmedName, email: trimmedEmail, password: password)
        }
    }

    private func supabaseSignUp(name: String, email: String, password: String) async {
        do {
            let result = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(name)]
            )
            userId = result.user.id.uuidString
            userName = name
            userEmail = email
            isSignedIn = true
            persistUserLocally()
            await createProfileIfNeeded()
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
            userId = session.user.id.uuidString
            userEmail = email
            userName = session.user.userMetadata["full_name"]?.value as? String ?? email
            isSignedIn = true
            persistUserLocally()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            return
        }
        Task {
            try? await supabase.auth.signOut()
        }
        if isGoogleConfigured {
            GIDSignIn.sharedInstance.signOut()
        }
        isSignedIn = false
        userName = ""
        userEmail = ""
        userProfileURL = nil
        userId = nil
        UserDefaults.standard.set(false, forKey: signedInKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
    }

    func deleteAccount(dataStore: DataStore) {
        Task {
            try? await supabase.auth.signOut()
        }
        dataStore.deleteAllData()
        signOut()
    }

    func signInWithApple() {
        guard isSupabaseConfigured else {
            errorMessage = "Cloud service is not configured. Please try again later."
            return
        }
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
            userId = session.user.id.uuidString
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
        guard isGoogleConfigured else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    func loadPendingInvitations() async {
        guard isSupabaseConfigured, !userEmail.isEmpty else { return }
        do {
            let invitations: [TeamInvitation] = try await supabase.from("invitations")
                .select()
                .eq("email", value: userEmail.lowercased())
                .eq("status", value: "pending")
                .execute()
                .value
            pendingInvitations = invitations
        } catch {
            print("Failed to load invitations: \(error)")
        }
    }

    func acceptInvitation(_ invitation: TeamInvitation) async {
        guard isSupabaseConfigured, let uid = userId else { return }
        do {
            let memberRecord = VineyardMemberRecord(
                id: nil,
                vineyard_id: invitation.vineyard_id,
                user_id: uid,
                name: userName,
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
        } catch {
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
                .eq("id", value: invitation.id.uuidString)
                .execute()

            pendingInvitations.removeAll { $0.id == invitation.id }
        } catch {
            errorMessage = "Failed to decline invitation: \(error.localizedDescription)"
        }
    }

    func inviteMember(email: String, role: VineyardRole, vineyardId: UUID, vineyardName: String) async -> Bool {
        guard isSupabaseConfigured, userId != nil else { return false }
        do {
            nonisolated struct InvitationParams: Codable, Sendable {
                let p_vineyard_id: String
                let p_vineyard_name: String
                let p_email: String
                let p_role: String
                let p_invited_by_name: String
            }
            let params = InvitationParams(
                p_vineyard_id: vineyardId.uuidString,
                p_vineyard_name: vineyardName,
                p_email: email.lowercased(),
                p_role: role.rawValue,
                p_invited_by_name: userName
            )
            try await supabase.rpc("create_invitation", params: params).execute()
            return true
        } catch {
            errorMessage = "Failed to send invitation: \(error.localizedDescription)"
            return false
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

    private func persistUserLocally() {
        UserDefaults.standard.set(true, forKey: signedInKey)
        UserDefaults.standard.set(userName, forKey: userNameKey)
        UserDefaults.standard.set(userEmail, forKey: userEmailKey)
    }

    private func updateGoogleUser(_ user: GIDGoogleUser) {
        userName = user.profile?.name ?? ""
        userEmail = user.profile?.email ?? ""
        userProfileURL = user.profile?.imageURL(withDimension: 120)
        persistUserLocally()
    }
}
