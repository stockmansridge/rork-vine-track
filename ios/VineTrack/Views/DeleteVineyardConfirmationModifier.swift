import SwiftUI

struct DeleteVineyardConfirmationModifier: ViewModifier {
    @Binding var vineyardPendingDeletion: Vineyard?
    let onConfirm: (Vineyard) -> Void

    @State private var showDeleteWarning: Bool = false
    @State private var showDeletePrompt: Bool = false
    @State private var shouldPresentTypedConfirmation: Bool = false
    @State private var deleteConfirmationText: String = ""

    private var normalizedDeleteConfirmationText: String {
        deleteConfirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: vineyardPendingDeletion?.id) { oldValue, newValue in
                guard oldValue != newValue, newValue != nil else { return }
                deleteConfirmationText = ""
                shouldPresentTypedConfirmation = false
                showDeleteWarning = true
            }
            .onChange(of: showDeleteWarning) { oldValue, newValue in
                guard oldValue, !newValue, shouldPresentTypedConfirmation, vineyardPendingDeletion != nil else { return }
                shouldPresentTypedConfirmation = false
                showDeletePrompt = true
            }
            .alert("Delete Vineyard?", isPresented: $showDeleteWarning, presenting: vineyardPendingDeletion) { _ in
                Button("Cancel", role: .cancel) {
                    reset()
                }
                Button("Yes") {
                    deleteConfirmationText = ""
                    shouldPresentTypedConfirmation = true
                }
            } message: { vineyard in
                Text("This will permanently delete \"\(vineyard.name)\" and all its data. This can't be undone.")
            }
            .alert("Type DELETE to confirm", isPresented: $showDeletePrompt, presenting: vineyardPendingDeletion) { vineyard in
                TextField("DELETE", text: $deleteConfirmationText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Delete Vineyard", role: .destructive) {
                    guard normalizedDeleteConfirmationText == "DELETE" else { return }
                    onConfirm(vineyard)
                    reset()
                }
                .disabled(normalizedDeleteConfirmationText != "DELETE")
                Button("Cancel", role: .cancel) {
                    reset()
                }
            } message: { vineyard in
                Text("Type DELETE to permanently remove \"\(vineyard.name)\".")
            }
    }

    private func reset() {
        vineyardPendingDeletion = nil
        showDeleteWarning = false
        showDeletePrompt = false
        deleteConfirmationText = ""
    }
}

extension View {
    func deleteVineyardConfirmation(
        vineyardPendingDeletion: Binding<Vineyard?>,
        onConfirm: @escaping (Vineyard) -> Void
    ) -> some View {
        modifier(
            DeleteVineyardConfirmationModifier(
                vineyardPendingDeletion: vineyardPendingDeletion,
                onConfirm: onConfirm
            )
        )
    }
}
