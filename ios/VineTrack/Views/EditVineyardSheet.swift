import SwiftUI

struct EditVineyardSheet: View {
    let vineyard: Vineyard?
    @Environment(DataStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    private var isEditing: Bool { vineyard != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vineyard Name") {
                    TextField("e.g. Barossa Valley Estate", text: $name)
                }

            }
            .navigationTitle(isEditing ? "Edit Vineyard" : "New Vineyard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveVineyard()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let vineyard {
                    name = vineyard.name
                }
            }
        }
    }

    private func saveVineyard() {
        if var existing = vineyard {
            existing.name = name
            store.updateVineyard(existing)
        } else {
            let currentUser = VineyardUser(
                id: UUID(uuidString: authService.userId ?? "") ?? UUID(),
                name: authService.userName.isEmpty ? authService.userEmail : authService.userName,
                role: .owner
            )
            let newVineyard = Vineyard(
                name: name,
                users: [currentUser],
                ownerId: UUID(uuidString: authService.userId ?? "")
            )
            store.addVineyard(newVineyard)
            store.selectVineyard(newVineyard)
        }
    }
}
