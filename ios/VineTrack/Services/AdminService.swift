import Foundation
import Supabase

nonisolated struct ProfileAdminCheck: Codable, Sendable {
    let is_admin: Bool
}

@Observable
@MainActor
class AdminService {
    var isAdmin: Bool = false
    var users: [AdminUser] = []
    var isLoading: Bool = false
    var errorMessage: String?



    func checkAdminStatus() async {
        guard isSupabaseConfigured else {
            isAdmin = false

            return
        }


        var currentUserId = "unknown"
        do {
            let session = try await supabase.auth.session
            currentUserId = session.user.id.uuidString

        } catch {
            isAdmin = false
            return
        }

        do {
            let result: Bool = try await supabase.rpc("is_current_user_admin").execute().value
            isAdmin = result

            if result { return }
        } catch {

        }

        do {
            let session = try await supabase.auth.session
            let userId = session.user.id
            let response: [ProfileAdminCheck] = try await supabase
                .from("profiles")
                .select("is_admin")
                .eq("id", value: userId)
                .execute()
                .value
            if let profile = response.first {
                isAdmin = profile.is_admin

            } else {
                isAdmin = false

            }
        } catch {
            isAdmin = false

        }
    }

    func fetchUsers() async {
        guard isSupabaseConfigured else { return }
        isLoading = true
        errorMessage = nil
        do {
            let result: [AdminUser] = try await supabase.rpc("get_admin_dashboard_users_safe").execute().value
            users = result
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            if Task.isCancelled { return }
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
        isLoading = false
    }

    var totalUsers: Int { users.count }

    var usersThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return users.filter { ($0.createdDate ?? .distantPast) > weekAgo }.count
    }

    var usersThisMonth: Int {
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return users.filter { ($0.createdDate ?? .distantPast) > monthAgo }.count
    }

    var activeUsers: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return users.filter { ($0.lastSignInDate ?? .distantPast) > weekAgo }.count
    }

    var totalVineyards: Int {
        let uniqueNames = Set(users.flatMap { $0.vineyardList })
        return uniqueNames.count
    }

    var googleUsers: Int {
        users.filter { $0.provider.lowercased() == "google" }.count
    }

    var emailUsers: Int {
        users.filter { $0.provider.lowercased() == "email" }.count
    }
}
