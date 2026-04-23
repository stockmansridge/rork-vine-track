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
            isOfflineSession = false
            persistUserLocally()
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
                data: ["full_name": .string(name)]
            )
            if result.session != nil {
                userId = result.user.id.uuidString
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

    private func clearDemoSessionIfNeeded() {
        guard isDemoMode else { return }
        isDemoMode = false
        isSignedIn = false
        userName = ""
        userEmail = ""
        userProfileURL = nil
        userId = nil
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
        isOfflineSession = false
        userName = ""
        userEmail = ""
        userProfileURL = nil
        userId = nil
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
            for invitation in invitations {
                await acceptInvitation(invitation)
            }
        } catch {
            print("Failed to load invitations: \(error)")
        }
    }

    func loadSentInvitations(vineyardId: UUID) async {
        guard isSupabaseConfigured else { return }
        do {
            let invitations: [TeamInvitation] = try await supabase.from("invitations")
                .select()
                .eq("vineyard_id", value: vineyardId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            sentInvitations = invitations
            print("[AuthService] loaded \(invitations.count) sent invitations for vineyard \(vineyardId.uuidString)")
        } catch {
            print("[AuthService] Failed to load sent invitations: \(error)")
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
            try await supabase.from("invitations")
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
            p_vineyard_id: vineyardId.uuidString,
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
                    vineyard_id: vineyardId.uuidString,
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
                errorMessage = "Failed to save invitation: \(error.localizedDescription). Run sql/create_invitation_rpc.sql in Supabase SQL Editor."
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
