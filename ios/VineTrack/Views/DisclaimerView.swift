import SwiftUI
import Supabase

struct DisclaimerView: View {
    @Environment(AuthService.self) private var authService
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    let onAccepted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(VineyardTheme.leafGreen)

                        Text("Disclaimer")
                            .font(.title.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("VineTrack is a support tool only. Any records, recommendations, or AI-generated information in the app are for general informational purposes and must be independently checked before use.")
                            .font(.subheadline)

                        Text("VineTrack does not provide professional agronomic, viticultural, disease, spray, legal, safety, or compliance advice. Users are solely responsible for verifying information and for all vineyard management decisions, including disease prevention and treatment.")
                            .font(.subheadline)

                        Text("To the maximum extent permitted by law, VineTrack accepts no liability for disease, crop loss, treatment outcomes, compliance issues, or any other loss arising from use of the app or reliance on AI-generated or user-entered information.")
                            .font(.subheadline)

                        Text("By tapping \"I Agree\", you confirm that you understand and accept this disclaimer.")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }

            VStack(spacing: 0) {
                Divider()
                Button {
                    acceptDisclaimer()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("I Agree")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(VineyardTheme.leafGreen)
                .disabled(isSubmitting)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
    }

    private func acceptDisclaimer() {
        guard let userId = authService.userId else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let record = DisclaimerInsert(
                    user_id: userId,
                    user_name: authService.userName,
                    user_email: authService.userEmail
                )
                try await supabase.from("disclaimer_acceptances")
                    .insert(record)
                    .execute()

                UserDefaults.standard.set(true, forKey: "vinetrack_disclaimer_accepted_\(userId)")
                onAccepted()
            } catch {
                errorMessage = "Failed to save acceptance. Please try again."
                isSubmitting = false
            }
        }
    }
}
