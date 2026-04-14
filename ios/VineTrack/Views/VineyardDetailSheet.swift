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
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if user.role != .owner && (accessControl?.canDelete ?? true) {
                        Button(role: .destructive) {
                            removeUser(user)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .contextMenu {
                    if user.role != .owner {
                        Menu("Change Role") {
                            ForEach(VineyardRole.allCases, id: \.self) { role in
                                if role != .owner {
                                    Button {
                                        changeRole(user: user, to: role)
                                    } label: {
                                        Label(role.rawValue, systemImage: role == user.role ? "checkmark" : "")
                                    }
                                }
                            }
                        }
                    }
                    Menu("Operator Category") {
                        Button {
                            assignOperatorCategory(user: user, categoryId: nil)
                        } label: {
                            Label("None", systemImage: user.operatorCategoryId == nil ? "checkmark" : "")
                        }
                        ForEach(store.operatorCategories) { cat in
                            Button {
                                assignOperatorCategory(user: user, categoryId: cat.id)
                            } label: {
                                Label("\(cat.name) ($\(String(format: "%.0f", cat.costPerHour))/hr)", systemImage: user.operatorCategoryId == cat.id ? "checkmark" : "")
                            }
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
            Text("Users assigned to this vineyard can access its blocks, pins, trips, and settings.")
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("User Details") {
                    TextField("Name", text: $userName)

                    Picker("Role", selection: $selectedRole) {
                        ForEach(VineyardRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
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
                        let newUser = VineyardUser(name: userName, role: selectedRole)
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
