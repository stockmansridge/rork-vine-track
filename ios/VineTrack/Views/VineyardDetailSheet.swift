import SwiftUI

struct RoleSummaryRow: View {
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct VineyardDetailSheet: View {
    let vineyard: Vineyard
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessControl) private var accessControl
    @Environment(AuditService.self) private var auditService
    @State private var showAddUser: Bool = false
    @State private var showEditName: Bool = false
    private var canManage: Bool { accessControl?.canManageUsers ?? false }
    @State private var editedName: String = ""
    @State private var selectedCountry: String = ""
    @State private var editingUser: VineyardUser?

    var body: some View {
        NavigationStack {
            List {
                vineyardInfoSection
                usersSection
                invitationsSection
                dangerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(vineyard.name)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                selectedCountry = vineyard.country
                if isSupabaseConfigured && canManage {
                    await authService.loadSentInvitations(vineyardId: vineyard.id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Vineyard", isPresented: $showEditName) {
                TextField("Vineyard name", text: $editedName)
                Button("Save") {
                    guard !editedName.isEmpty else { return }
                    var updated = vineyard
                    updated.name = editedName
                    store.updateVineyard(updated)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAddUser, onDismiss: {
                if isSupabaseConfigured && canManage {
                    Task { await authService.loadSentInvitations(vineyardId: vineyard.id) }
                }
            }) {
                if isSupabaseConfigured {
                    InviteMemberSheet(vineyard: vineyard)
                } else {
                    AddUserSheet(vineyard: vineyard)
                }
            }
            .sheet(item: $editingUser) { user in
                EditUserSheet(vineyard: vineyard, user: user)
            }
        }
    }

    private static let wineCountries: [String] = [
        "Australia",
        "Argentina",
        "Austria",
        "Brazil",
        "Canada",
        "Chile",
        "China",
        "France",
        "Germany",
        "Greece",
        "Hungary",
        "India",
        "Israel",
        "Italy",
        "Japan",
        "Mexico",
        "New Zealand",
        "Portugal",
        "Romania",
        "South Africa",
        "Spain",
        "Switzerland",
        "United Kingdom",
        "United States",
        "Uruguay"
    ]

    private var vineyardInfoSection: some View {
        Section {
            LabeledContent("Name", value: vineyard.name)
            LabeledContent("Created", value: vineyard.createdAt.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Users", value: "\(vineyard.users.count)")

            Picker("Country", selection: $selectedCountry) {
                Text("Not Set").tag("")
                ForEach(Self.wineCountries, id: \.self) { country in
                    Text(country).tag(country)
                }
            }
            .onChange(of: selectedCountry) { _, newValue in
                var updated = vineyard
                updated.country = newValue
                store.updateVineyard(updated)
            }

            Button {
                editedName = vineyard.name
                showEditName = true
            } label: {
                Label("Rename Vineyard", systemImage: "pencil")
            }
        } header: {
            Text("Vineyard Info")
        } footer: {
            if !selectedCountry.isEmpty {
                Text("Chemical searches will prioritize products available in \(selectedCountry).")
            }
        }
    }

    private var usersSection: some View {
        Section {
            ForEach(vineyard.users) { user in
                Button {
                    if canManage { editingUser = user }
                } label: {
                userRow(user)
                }
                .buttonStyle(.plain)
                .disabled(!canManage)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if user.role != .owner && canManage {
                        Button(role: .destructive) {
                            removeUser(user)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }

            if canManage {
                Button {
                    showAddUser = true
                } label: {
                    Label(isSupabaseConfigured ? "Add User" : "Add User (Local)", systemImage: "person.badge.plus")
                }
            }
        } header: {
            Text("Users")
        } footer: {
            if canManage {
                Text(isSupabaseConfigured
                    ? "Add users by sending an email invitation. Tap a user to edit their role and operator category. Role controls app access; operator category sets their hourly rate for trip and task reports."
                    : "Tap a user to edit their role and operator category.")
            } else {
                Text("Only Managers can add, edit or remove users.")
            }
        }
    }

    @ViewBuilder
    private func userRow(_ user: VineyardUser) -> some View {
        HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(roleColor(user.role).gradient)
                            .frame(width: 36, height: 36)
                        Text(String(user.name.prefix(1)).uppercased())
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.headline)
                        HStack(spacing: 4) {
                            Text(user.role.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let catId = user.operatorCategoryId,
                               let cat = store.operatorCategories.first(where: { $0.id == catId }) {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if accessControl?.canViewFinancials ?? false {
                                    Text("\(cat.name) $\(String(format: "%.0f", cat.costPerHour))/hr")
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                } else {
                                    Text(cat.name)
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                    }

                    Spacer()

                    if user.role == .owner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var invitationsSection: some View {
        if isSupabaseConfigured && canManage {
            Section {
                if authService.sentInvitations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .foregroundStyle(.secondary)
                        Text("No invitations sent yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(authService.sentInvitations) { invitation in
                        invitationRow(invitation)
                    }
                }
            } header: {
                HStack {
                    Text("Invitations")
                    Spacer()
                    Button {
                        Task { await authService.loadSentInvitations(vineyardId: vineyard.id) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            } footer: {
                Text("People you've invited appear here. Pending invitations haven't been accepted yet; accepted invitations mean the user has joined and appears above. You can resend or cancel any invitation.")
            }
        }
    }

    @ViewBuilder
    private func invitationRow(_ invitation: TeamInvitation) -> some View {
        let status = invitation.status.lowercased()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor(status).gradient)
                        .frame(width: 36, height: 36)
                    Image(systemName: statusIcon(status))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.email)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(invitation.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(statusLabel(status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor(status))
                        if let sent = formattedSentDate(invitation.created_at) {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(sent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    Task { _ = await authService.resendInvitation(invitation) }
                } label: {
                    Label(status == "pending" ? "Resend" : "Re-invite", systemImage: "paperplane")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    Task { _ = await authService.cancelInvitation(invitation) }
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending": return .orange
        case "accepted": return VineyardTheme.leafGreen
        case "declined": return .red
        default: return .gray
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "pending": return "clock.fill"
        case "accepted": return "checkmark"
        case "declined": return "xmark"
        default: return "envelope"
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "pending": return "Pending"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        default: return status.capitalized
        }
    }

    private func formattedSentDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return rel.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private var dangerSection: some View {
        if accessControl?.canDelete ?? false {
            Section {
                Button(role: .destructive) {
                    store.deleteVineyard(vineyard)
                    dismiss()
                } label: {
                    Label("Delete Vineyard", systemImage: "trash")
                }
            } footer: {
                Text("This will permanently delete the vineyard and all its data.")
            }
        }
    }

    private func removeUser(_ user: VineyardUser) {
        var updated = vineyard
        updated.users.removeAll { $0.id == user.id }
        store.updateVineyard(updated)
        auditService.log(
            action: .userRemoved,
            entityType: "VineyardUser",
            entityId: user.id.uuidString,
            entityLabel: user.name,
            details: "Role: \(user.role.rawValue)"
        )
    }

    private func changeRole(user: VineyardUser, to newRole: VineyardRole) {
        var updated = vineyard
        guard let index = updated.users.firstIndex(where: { $0.id == user.id }) else { return }
        let oldRole = updated.users[index].role
        updated.users[index].role = newRole
        store.updateVineyard(updated)
        auditService.log(
            action: .roleChanged,
            entityType: "VineyardUser",
            entityId: user.id.uuidString,
            entityLabel: user.name,
            details: "\(oldRole.rawValue) → \(newRole.rawValue)"
        )
    }

    private func assignOperatorCategory(user: VineyardUser, categoryId: UUID?) {
        var updated = vineyard
        guard let index = updated.users.firstIndex(where: { $0.id == user.id }) else { return }
        updated.users[index].operatorCategoryId = categoryId
        store.updateVineyard(updated)
    }

    private func roleColor(_ role: VineyardRole) -> Color {
        switch role {
        case .owner: return .orange
        case .manager: return .blue
        case .supervisor: return .purple
        case .operator_: return .green
        }
    }
}

struct AddUserSheet: View {
    let vineyard: Vineyard
    @Environment(DataStore.self) private var store
    @Environment(AuditService.self) private var auditService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessControl) private var accessControl
    @State private var userName: String = ""
    @State private var selectedRole: VineyardRole = .operator_
    @State private var selectedCategoryId: UUID? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $userName)
                } header: {
                    Text("User Details")
                }

                Section {
                    Picker("Role", selection: $selectedRole) {
                        ForEach(VineyardRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        RoleSummaryRow(title: "Operator", text: "Basic staff — records work, no deletes or financials.")
                        RoleSummaryRow(title: "Supervisor", text: "Manages operations and deletes, no financials.")
                        RoleSummaryRow(title: "Manager", text: "Full access, including financials, setup and team.")
                    }
                    .padding(.vertical, 4)

                    NavigationLink {
                        RolesPermissionsInfoView()
                    } label: {
                        Label("Learn more about roles", systemImage: "info.circle")
                            .font(.footnote)
                    }
                } header: {
                    Text("Role")
                } footer: {
                    Text("Some features and values are hidden based on the assigned role.")
                }

                Section {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.operatorCategories) { cat in
                            if accessControl?.canViewFinancials ?? false {
                                Text("\(cat.name) ($\(String(format: "%.0f", cat.costPerHour))/hr)")
                                    .tag(UUID?.some(cat.id))
                            } else {
                                Text(cat.name)
                                    .tag(UUID?.some(cat.id))
                            }
                        }
                    }
                } header: {
                    Text("Operator Category")
                } footer: {
                    Text("Sets the hourly rate used in trip and task cost reports. Manage categories in Settings → Spray Management → Operator Categories.")
                }
            }
            .navigationTitle("Add User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let newUser = VineyardUser(
                            name: userName,
                            role: selectedRole,
                            operatorCategoryId: selectedCategoryId
                        )
                        var updated = vineyard
                        updated.users.append(newUser)
                        store.updateVineyard(updated)
                        auditService.log(
                            action: .userAdded,
                            entityType: "VineyardUser",
                            entityId: newUser.id.uuidString,
                            entityLabel: newUser.name,
                            details: "Role: \(selectedRole.rawValue)"
                        )
                        dismiss()
                    }
                    .disabled(userName.isEmpty)
                }
            }
        }
    }
}

struct EditUserSheet: View {
    let vineyard: Vineyard
    let user: VineyardUser
    @Environment(DataStore.self) private var store
    @Environment(AuditService.self) private var auditService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessControl) private var accessControl
    @State private var userName: String = ""
    @State private var selectedRole: VineyardRole = .operator_
    @State private var selectedCategoryId: UUID? = nil

    private var isOwner: Bool { user.role == .owner }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $userName)
                } header: {
                    Text("User Details")
                }

                Section {
                    if isOwner {
                        LabeledContent("Role", value: user.role.rawValue)
                    } else {
                        Picker("Role", selection: $selectedRole) {
                            ForEach(VineyardRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                                Text(role.rawValue).tag(role)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            RoleSummaryRow(title: "Operator", text: "Basic staff — records work, no deletes or financials.")
                            RoleSummaryRow(title: "Supervisor", text: "Manages operations and deletes, no financials.")
                            RoleSummaryRow(title: "Manager", text: "Full access, including financials, setup and team.")
                        }
                        .padding(.vertical, 4)

                        NavigationLink {
                            RolesPermissionsInfoView()
                        } label: {
                            Label("Learn more about roles", systemImage: "info.circle")
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("Role")
                } footer: {
                    Text(isOwner ? "The Owner role cannot be changed." : "Some features and values are hidden based on the assigned role.")
                }

                Section {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.operatorCategories) { cat in
                            if accessControl?.canViewFinancials ?? false {
                                Text("\(cat.name) ($\(String(format: "%.0f", cat.costPerHour))/hr)")
                                    .tag(UUID?.some(cat.id))
                            } else {
                                Text(cat.name)
                                    .tag(UUID?.some(cat.id))
                            }
                        }
                    }
                    if store.operatorCategories.isEmpty {
                        Text("No categories defined yet. Add them in Settings → Spray Management → Operator Categories.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Operator Category")
                } footer: {
                    Text("Sets the hourly rate used in trip and task cost reports. This is independent of the user's role.")
                }
            }
            .navigationTitle("Edit User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                userName = user.name
                selectedRole = user.role == .owner ? .operator_ : user.role
                selectedCategoryId = user.operatorCategoryId
            }
        }
    }

    private func save() {
        var updated = vineyard
        guard let idx = updated.users.firstIndex(where: { $0.id == user.id }) else {
            dismiss()
            return
        }
        let oldRole = updated.users[idx].role
        updated.users[idx].name = userName.trimmingCharacters(in: .whitespaces)
        if !isOwner {
            updated.users[idx].role = selectedRole
        }
        updated.users[idx].operatorCategoryId = selectedCategoryId
        store.updateVineyard(updated)
        if !isOwner && oldRole != selectedRole {
            auditService.log(
                action: .roleChanged,
                entityType: "VineyardUser",
                entityId: user.id.uuidString,
                entityLabel: user.name,
                details: "\(oldRole.rawValue) → \(selectedRole.rawValue)"
            )
        }
        dismiss()
    }
}
