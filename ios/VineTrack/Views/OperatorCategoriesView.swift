import SwiftUI

struct OperatorCategoriesView: View {
    @Environment(DataStore.self) private var store
    @State private var showAddSheet: Bool = false
    @State private var editingCategory: OperatorCategory?

    var body: some View {
        List {
            Section {
                ForEach(store.operatorCategories) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(String(format: "$%.2f /hr", category.costPerHour))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteOperatorCategory(category)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Category", systemImage: "plus.circle")
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Define operator categories with hourly rates. Assign them to vineyard users to calculate operator costs on trip reports.")
            }
        }
        .navigationTitle("Operator Categories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            OperatorCategoryFormSheet(category: nil)
        }
        .sheet(item: $editingCategory) { category in
            OperatorCategoryFormSheet(category: category)
        }
    }
}

struct OperatorCategoryFormSheet: View {
    let category: OperatorCategory?
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var costString: String = ""
    @State private var assignedUserIds: Set<UUID> = []

    private var isEditing: Bool { category != nil }

    private var vineyardUsers: [VineyardUser] {
        guard let vineyardId = store.selectedVineyardId,
              let vineyard = store.vineyards.first(where: { $0.id == vineyardId }) else { return [] }
        return vineyard.users
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Category Name", text: $name)
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Cost per hour", text: $costString)
                            .keyboardType(.decimalPad)
                        Text("/hr")
                            .foregroundStyle(.secondary)
                    }
                }

                if !vineyardUsers.isEmpty {
                    Section {
                        ForEach(vineyardUsers) { user in
                            Button {
                                toggleUser(user.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: assignedUserIds.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(assignedUserIds.contains(user.id) ? .blue : .secondary)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text(user.role.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text("Assign Users")
                    } footer: {
                        Text("Select users to assign to this operator category. Their cost will be calculated using the hourly rate above.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let category {
                    name = category.name
                    costString = category.costPerHour > 0 ? String(format: "%.2f", category.costPerHour) : ""
                    assignedUserIds = Set(vineyardUsers.filter { $0.operatorCategoryId == category.id }.map { $0.id })
                }
            }
        }
    }

    private func toggleUser(_ userId: UUID) {
        if assignedUserIds.contains(userId) {
            assignedUserIds.remove(userId)
        } else {
            assignedUserIds.insert(userId)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let cost = Double(costString) ?? 0

        var categoryId: UUID
        if var existing = category {
            existing.name = trimmedName
            existing.costPerHour = cost
            store.updateOperatorCategory(existing)
            categoryId = existing.id
        } else {
            let newCategory = OperatorCategory(
                vineyardId: store.selectedVineyardId ?? UUID(),
                name: trimmedName,
                costPerHour: cost
            )
            store.addOperatorCategory(newCategory)
            categoryId = newCategory.id
        }

        guard let vineyardId = store.selectedVineyardId,
              let vineyardIndex = store.vineyards.firstIndex(where: { $0.id == vineyardId }) else {
            dismiss()
            return
        }
        var updated = store.vineyards[vineyardIndex]
        for i in updated.users.indices {
            if assignedUserIds.contains(updated.users[i].id) {
                updated.users[i].operatorCategoryId = categoryId
            } else if updated.users[i].operatorCategoryId == categoryId {
                updated.users[i].operatorCategoryId = nil
            }
        }
        store.updateVineyard(updated)
        dismiss()
    }
}
