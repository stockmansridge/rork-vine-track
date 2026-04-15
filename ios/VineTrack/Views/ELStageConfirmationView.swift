import SwiftUI

struct ELStageConfirmationView: View {
    let stage: GrowthStage
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(spacing: 20) {
                    stageImageCard
                    stageInfoSection
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }

            actionButtons
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headerBar: some View {
        VStack(spacing: 4) {
            Text("Confirm Growth Stage")
                .font(.headline)
            Text("Does this match what you see in the vineyard?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var stageImageCard: some View {
        Group {
            if let imageName = stage.imageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
        }
    }

    private var stageInfoSection: some View {
        VStack(spacing: 8) {
            Text(stage.code)
                .font(.title.weight(.bold))
                .foregroundStyle(.green)

            Text(stage.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onBack()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.tertiarySystemGroupedBackground))
                .foregroundStyle(.primary)
                .clipShape(.rect(cornerRadius: 12))
            }

            Button {
                onConfirm()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("Confirm")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green.gradient)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
