import SwiftUI

struct VineyardDetailSheet: View {
    let vineyard: Vineyard
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessControl) private var accessControl
    @State private var showAddUser: Bool = false
    @State private var showEditName: Bool = false
    @State private var showInviteMember: Bool = false
    @State private var editedName: String = ""
    @State private var selectedCountry: String = ""
    @State private var editingUser: VineyardUser?

    var body: some View {
        NavigationStack {
            List {
                vineyardInfoSection
                usersSection
                dangerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(vineyard.name)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                selectedCountry = vineyard.country
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
            .sheet(isPresented: $showAddUser) {
                AddUserSheet(vineyard: vineyard)
            }
            .sheet(isPresented: $showInviteMember) {
                InviteMemberSheet(vineyard: vineyard)
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
                    editingUser = user
                } label: {
                userRow(user)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if user.role != .owner && (accessControl?.canDelete ?? true) {
                        Button(role: .destructive) {
                            removeUser(user)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                showAddUser = true
            } label: {
                Label("Add User", systemImage: "person.badge.plus")
            }

            if isSupabaseConfigured {
                Button {
                    showInviteMember = true
                } label: {
                    Label("Invite by Email", systemImage: "envelope.badge.person.crop")
                        .foregroundStyle(.blue)
                }
            }
        } header: {
            Text("Users")
        } footer: {
            Text("Tap a user to edit their role and operator category. Role controls app access; operator category sets their hourly rate for trip reports.")
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
                                Text("\(cat.name) $\(String(format: "%.0f", cat.costPerHour))/hr")
                                    .font(.caption)
                                    .foregroundStyle(.teal)
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
    private var dangerSection: some View {
        if accessControl?.canDelete ?? true {
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
    }

    private func changeRole(user: VineyardUser, to newRole: VineyardRole) {
        var updated = vineyard
        guard let index = updated.users.firstIndex(where: { $0.id == user.id }) else { return }
        updated.users[index].role = newRole
        store.updateVineyard(updated)
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
        case .operator_: return .green
        }
    }
}

struct AddUserSheet: View {
    let vineyard: Vineyard
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
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
                } header: {
                    Text("Role")
                } footer: {
                    Text("Controls access to features in the app. Managers can edit settings; Operators can log trips and view data.")
                }

                Section {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.operatorCategories) { cat in
                            Text("\(cat.name) ($\(String(format: "%.0f", cat.costPerHour))/hr)")
                                .tag(UUID?.some(cat.id))
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
    @Environment(\.dismiss) private var dismiss
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
                    }
                } header: {
                    Text("Role")
                } footer: {
                    Text(isOwner
                        ? "The Owner role cannot be changed."
                        : "Controls access to features in the app. Managers can edit settings; Operators can log trips and view data.")
                }

                Section {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.operatorCategories) { cat in
                            Text("\(cat.name) ($\(String(format: "%.0f", cat.costPerHour))/hr)")
                                .tag(UUID?.some(cat.id))
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
        updated.users[idx].name = userName.trimmingCharacters(in: .whitespaces)
        if !isOwner {
            updated.users[idx].role = selectedRole
        }
        updated.users[idx].operatorCategoryId = selectedCategoryId
        store.updateVineyard(updated)
        dismiss()
    }
}
