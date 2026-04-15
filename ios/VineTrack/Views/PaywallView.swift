import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(StoreViewModel.self) private var storeVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    featuresSection

                    if storeVM.isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .padding(.top, 20)
                    } else if let current = storeVM.offerings?.current {
                        packagesSection(current)
                    } else {
                        ContentUnavailableView(
                            "Unable to Load Plans",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Please check your connection and try again.")
                        )
                    }

                    restoreButton
                    legalText
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Error", isPresented: .init(
                get: { storeVM.error != nil },
                set: { if !$0 { storeVM.error = nil } }
            )) {
                Button("OK") { storeVM.error = nil }
            } message: {
                Text(storeVM.error ?? "")
            }
            .task {
                await storeVM.fetchOfferings()
            }
            .onChange(of: storeVM.isPremium) { _, isPremium in
                if isPremium { dismiss() }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            GrapeLeafIcon(size: 64)
                .foregroundStyle(VineyardTheme.leafGreen.gradient)
                .padding(.top, 24)

            Text("VineTrack Pro")
                .font(.largeTitle.bold())

            Text("Unlock the full power of vineyard management")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "icloud.fill", color: .blue, title: "Cloud Sync", subtitle: "Sync data across all your devices")
            featureRow(icon: "doc.text.fill", color: .purple, title: "PDF & XLS Export", subtitle: "Generate professional reports")
            featureRow(icon: "map.fill", color: .orange, title: "Unlimited Blocks", subtitle: "No limits on blocks and pins")
            featureRow(icon: "spray.fill", color: VineyardTheme.leafGreen, title: "Spray Records", subtitle: "Full spray program management")
            featureRow(icon: "chart.bar.fill", color: .teal, title: "Growth Reports", subtitle: "Detailed growth stage analytics")
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func packagesSection(_ offering: Offering) -> some View {
        VStack(spacing: 12) {
            ForEach(offering.availablePackages, id: \.identifier) { package in
                packageCard(package)
            }
        }
    }

    private func packageCard(_ package: Package) -> some View {
        let isAnnual = package.identifier == "$rc_annual"

        return Button {
            Task { await storeVM.purchase(package: package) }
        } label: {
            VStack(spacing: 6) {
                if isAnnual {
                    Text("BEST VALUE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(VineyardTheme.leafGreen.gradient, in: Capsule())
                }

                Text(package.storeProduct.localizedTitle)
                    .font(.headline)

                Text(package.storeProduct.localizedPriceString)
                    .font(.title2.bold())

                if let intro = package.storeProduct.introductoryDiscount {
                    Text("Free for \(intro.subscriptionPeriod.value) \(intro.subscriptionPeriod.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isAnnual {
                    Text("per year")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("per month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal)
            .background(isAnnual ? VineyardTheme.leafGreen : Color.accentColor, in: .rect(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(storeVM.isPurchasing)
        .opacity(storeVM.isPurchasing ? 0.7 : 1)
    }

    private var restoreButton: some View {
        Button {
            Task { await storeVM.restore() }
        } label: {
            Text("Restore Purchases")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var legalText: some View {
        VStack(spacing: 8) {
            Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Link("Terms of Use (EULA)", destination: AppLinks.termsOfUse)
                Text("and")
                    .foregroundStyle(.tertiary)
                Link("Privacy Policy", destination: AppLinks.privacyPolicy)
            }
            .font(.caption2)
        }
    }
}
