import SwiftUI

enum StatFilter: String, Identifiable {
    case totalUsers = "Total Users"
    case activeUsers = "Active Users (7d)"
    case newThisWeek = "New This Week"
    case newThisMonth = "New This Month"
    case vineyards = "Vineyards"
    case avgVineyards = "Users by Vineyard Count"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .totalUsers: return "person.2.fill"
        case .activeUsers: return "bolt.fill"
        case .newThisWeek: return "calendar.badge.plus"
        case .newThisMonth: return "chart.line.uptrend.xyaxis"
        case .vineyards: return "leaf.fill"
        case .avgVineyards: return "chart.bar.fill"
        }
    }

    var color: Color {
        switch self {
        case .totalUsers: return .blue
        case .activeUsers: return .green
        case .newThisWeek: return .orange
        case .newThisMonth: return .purple
        case .vineyards: return .mint
        case .avgVineyards: return .indigo
        }
    }
}

struct AdminDashboardView: View {
    @Environment(AdminService.self) private var adminService
    @State private var searchText: String = ""
    @State private var selectedUser: AdminUser?
    @State private var selectedStat: StatFilter?
    @State private var sortOrder: SortOrder = .newest

    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case lastActive = "Last Active"
        case name = "Name"
    }

    private var filteredUsers: [AdminUser] {
        var result = adminService.users
        if !searchText.isEmpty {
            result = result.filter {
                $0.full_name.localizedCaseInsensitiveContains(searchText) ||
                $0.email.localizedCaseInsensitiveContains(searchText) ||
                $0.vineyard_names.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .newest:
            result.sort { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        case .oldest:
            result.sort { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) }
        case .lastActive:
            result.sort { ($0.lastSignInDate ?? .distantPast) > ($1.lastSignInDate ?? .distantPast) }
        case .name:
            result.sort { $0.full_name.localizedCompare($1.full_name) == .orderedAscending }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if adminService.isLoading {
                        ProgressView("Loading dashboard...")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = adminService.errorMessage {
                        errorCard(error)
                    } else {
                        statsGrid
                        signupMethodCard
                        sortPicker
                        usersList
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Admin Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search users, emails, vineyards...")
            .refreshable {
                await adminService.fetchUsers()
            }
            .sheet(item: $selectedUser) { user in
                AdminUserDetailSheet(user: user)
            }
            .sheet(item: $selectedStat) { stat in
                StatDetailSheet(filter: stat, users: adminService.users)
            }
            .task {
                if adminService.users.isEmpty {
                    await adminService.fetchUsers()
                }
            }
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            Button { selectedStat = .totalUsers } label: {
                StatCard(
                    title: "Total Users",
                    value: "\(adminService.totalUsers)",
                    icon: "person.2.fill",
                    color: .blue
                )
            }
            .buttonStyle(.plain)

            Button { selectedStat = .activeUsers } label: {
                StatCard(
                    title: "Active (7d)",
                    value: "\(adminService.activeUsers)",
                    icon: "bolt.fill",
                    color: VineyardTheme.leafGreen
                )
            }
            .buttonStyle(.plain)

            Button { selectedStat = .newThisWeek } label: {
                StatCard(
                    title: "New This Week",
                    value: "\(adminService.usersThisWeek)",
                    icon: "calendar.badge.plus",
                    color: .orange
                )
            }
            .buttonStyle(.plain)

            Button { selectedStat = .newThisMonth } label: {
                StatCard(
                    title: "New This Month",
                    value: "\(adminService.usersThisMonth)",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple
                )
            }
            .buttonStyle(.plain)

            Button { selectedStat = .vineyards } label: {
                StatCard(
                    title: "Vineyards",
                    value: "\(adminService.totalVineyards)",
                    icon: "leaf.fill",
                    color: .mint
                )
            }
            .buttonStyle(.plain)

            Button { selectedStat = .avgVineyards } label: {
                StatCard(
                    title: "Avg Vineyards",
                    value: adminService.totalUsers > 0
                        ? String(format: "%.1f", Double(adminService.users.reduce(0) { $0 + $1.vineyard_count }) / Double(adminService.totalUsers))
                        : "0",
                    icon: "chart.bar.fill",
                    color: .indigo
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var signupMethodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign-up Methods")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                signupMethodBar(label: "Google", count: adminService.googleUsers, color: .red)
                signupMethodBar(label: "Email", count: adminService.emailUsers, color: .blue)
            }
        }
        .padding()
        .background(.background, in: .rect(cornerRadius: 12))
    }

    private func signupMethodBar(label: String, count: Int, color: Color) -> some View {
        let total = max(adminService.totalUsers, 1)
        let percentage = Double(count) / Double(total)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(geo.size.width * percentage, 4))
                }
            }
            .frame(height: 8)
        }
    }

    private var sortPicker: some View {
        HStack {
            Text("\(filteredUsers.count) user\(filteredUsers.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        Label(order.rawValue, systemImage: sortOrder == order ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortOrder.rawValue)
                        .font(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var usersList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredUsers) { user in
                AdminUserRow(user: user)
                    .onTapGesture {
                        selectedUser = user
                    }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await adminService.fetchUsers() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: .rect(cornerRadius: 12))
    }
}

struct AdminUserRow: View {
    let user: AdminUser

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(providerColor.gradient)
                    .frame(width: 40, height: 40)
                Text(user.full_name.prefix(1).uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.full_name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if user.is_admin {
                        Text("ADMIN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.red.gradient, in: Capsule())
                    }
                }
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if user.vineyard_count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(VineyardTheme.leafGreen)
                        Text("\(user.vineyard_count)")
                            .font(.caption.weight(.medium))
                    }
                }
                if let date = user.createdDate {
                    Text(date, style: .date)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 12))
    }

    private var providerColor: Color {
        switch user.provider.lowercased() {
        case "google": return .red
        default: return .blue
        }
    }
}

struct StatDetailSheet: View {
    let filter: StatFilter
    let users: [AdminUser]
    @Environment(\.dismiss) private var dismiss

    private var filteredUsers: [AdminUser] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()

        switch filter {
        case .totalUsers:
            return users.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        case .activeUsers:
            return users.filter { ($0.lastSignInDate ?? .distantPast) > weekAgo }
                .sorted { ($0.lastSignInDate ?? .distantPast) > ($1.lastSignInDate ?? .distantPast) }
        case .newThisWeek:
            return users.filter { ($0.createdDate ?? .distantPast) > weekAgo }
                .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        case .newThisMonth:
            return users.filter { ($0.createdDate ?? .distantPast) > monthAgo }
                .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        case .vineyards, .avgVineyards:
            return users.filter { $0.vineyard_count > 0 }
                .sorted { $0.vineyard_count > $1.vineyard_count }
        }
    }

    private var allVineyards: [(name: String, ownerCount: Int)] {
        var vineyardOwners: [String: Int] = [:]
        for user in users {
            for name in user.vineyardList {
                vineyardOwners[name, default: 0] += 1
            }
        }
        return vineyardOwners.map { (name: $0.key, ownerCount: $0.value) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filter == .vineyards {
                    vineyardListView
                } else {
                    userListView
                }
            }
            .navigationTitle(filter.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var userListView: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: filter.icon)
                        .font(.title2)
                        .foregroundStyle(filter.color)
                        .frame(width: 44, height: 44)
                        .background(filter.color.opacity(0.12), in: .rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(filteredUsers.count)")
                            .font(.title.weight(.bold))
                        Text(filter.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("\(filteredUsers.count) user\(filteredUsers.count == 1 ? "" : "s")") {
                ForEach(filteredUsers) { user in
                    StatUserRow(user: user, filter: filter)
                }
            }
        }
    }

    private var vineyardListView: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.title2)
                        .foregroundStyle(.mint)
                        .frame(width: 44, height: 44)
                        .background(Color.mint.opacity(0.12), in: .rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(allVineyards.count)")
                            .font(.title.weight(.bold))
                        Text("Total Vineyards")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("\(allVineyards.count) vineyard\(allVineyards.count == 1 ? "" : "s")") {
                ForEach(allVineyards, id: \.name) { vineyard in
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(VineyardTheme.leafGreen)
                            .frame(width: 32, height: 32)
                            .background(VineyardTheme.leafGreen.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vineyard.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(vineyard.ownerCount) member\(vineyard.ownerCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

struct StatUserRow: View {
    let user: AdminUser
    let filter: StatFilter

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(providerColor.gradient)
                    .frame(width: 36, height: 36)
                Text(user.full_name.prefix(1).uppercased())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.full_name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                switch filter {
                case .activeUsers:
                    if let date = user.lastSignInDate {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case .newThisWeek, .newThisMonth, .totalUsers:
                    if let date = user.createdDate {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case .avgVineyards:
                    HStack(spacing: 3) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(VineyardTheme.leafGreen)
                        Text("\(user.vineyard_count)")
                            .font(.caption.weight(.semibold))
                    }
                case .vineyards:
                    EmptyView()
                }
            }
        }
    }

    private var providerColor: Color {
        switch user.provider.lowercased() {
        case "google": return .red
        default: return .blue
        }
    }
}

struct AdminUserDetailSheet: View {
    let user: AdminUser
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(providerColor.gradient)
                                    .frame(width: 72, height: 72)
                                Text(user.full_name.prefix(1).uppercased())
                                    .font(.title.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            Text(user.full_name)
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 6) {
                                if user.is_admin {
                                    Text("ADMIN")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.red.gradient, in: Capsule())
                                }
                                Text(user.providerDisplay)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Contact") {
                    LabeledContent("Email", value: user.email)
                    LabeledContent("User ID", value: user.user_id.uuidString.prefix(8) + "...")
                }

                Section("Activity") {
                    if let date = user.createdDate {
                        LabeledContent("Signed Up") {
                            VStack(alignment: .trailing) {
                                Text(date, style: .date)
                                Text(date, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let date = user.lastSignInDate {
                        LabeledContent("Last Sign In") {
                            VStack(alignment: .trailing) {
                                Text(date, style: .relative)
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent("Sign-up Method", value: user.providerDisplay)
                }

                Section("Vineyards (\(user.vineyard_count))") {
                    if user.vineyardList.isEmpty {
                        Text("No vineyards")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(user.vineyardList, id: \.self) { name in
                            HStack(spacing: 10) {
                                Image(systemName: "leaf.fill")
                                    .foregroundStyle(VineyardTheme.leafGreen)
                                    .font(.subheadline)
                                Text(name)
                            }
                        }
                    }
                    LabeledContent("Total Members Across Vineyards", value: "\(user.total_members)")
                }
            }
            .navigationTitle("User Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var providerColor: Color {
        switch user.provider.lowercased() {
        case "google": return .red
        default: return .blue
        }
    }
}
