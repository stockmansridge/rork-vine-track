import SwiftUI

struct OnboardingView: View {
    @State private var currentPage: Int = 0
    var onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "leaf.fill",
            iconColor: .green,
            title: "Welcome to VineTrack",
            subtitle: "Your vineyard management companion",
            description: "Track repairs, monitor growth stages, record spray programs, and manage your entire vineyard operation — all from the cab of your tractor.",
            tips: []
        ),
        OnboardingPage(
            icon: "map.fill",
            iconColor: .blue,
            title: "Set Up Your Vineyard",
            subtitle: "Define your blocks and rows",
            description: "Create your vineyard, add paddocks with row configurations, and draw boundaries on the map. Invite team members so everyone stays in sync.",
            tips: [
                "Go to Settings → Vineyard to create your first vineyard",
                "Add paddocks with row count and orientation",
                "Draw block boundaries on the map for accurate tracking",
                "Invite team members to collaborate across your vineyard"
            ]
        ),
        OnboardingPage(
            icon: "mappin.and.ellipse",
            iconColor: .red,
            title: "Drop Pins as You Drive",
            subtitle: "Mark repairs and growth stages",
            description: "Mount your phone and tap the customisable buttons to log issues on either side of you. Pins are geo-tagged with paddock and row number automatically.",
            tips: [
                "Switch between Repairs and Growth modes",
                "Pins auto-detect your paddock and row number",
                "Optionally snap a photo with each pin",
                "Customise button labels and colours in Settings"
            ]
        ),
        OnboardingPage(
            icon: "location.north.fill",
            iconColor: .orange,
            title: "Track Your Trips",
            subtitle: "GPS-tracked vineyard walks",
            description: "Start a trip to track your path through the vineyard. Rows auto-complete as you walk them, and you can record detailed spray data for each run.",
            tips: [
                "Select a paddock and tracking pattern to begin",
                "GPS tracks your position and completes rows automatically",
                "Record spray details — chemicals, rates, weather, and tank mixes",
                "View a summary of completed, skipped, and remaining rows"
            ]
        ),
        OnboardingPage(
            icon: "drop.fill",
            iconColor: .cyan,
            title: "Spray Programs",
            subtitle: "Detailed spray recording & tracking",
            description: "Log every spray application with chemicals, rates, weather conditions, and multi-tank mixes. Save chemical presets to speed up future records.",
            tips: [
                "Auto-fetch live weather data for accurate spray logs",
                "Save chemical presets for quick re-use",
                "Track fan/jet count, speed, and spray references",
                "Export spray records to PDF for compliance"
            ]
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            iconColor: .pink,
            title: "Yield Determination",
            subtitle: "Estimate crop yields per block",
            description: "Pick a paddock and the calculator pulls in vines/ha, spurs/vine, buds/spur, and bunches/bud. Add bunch weight to get kg/ha, t/ha, and total block yield — with support for cane or spur pruning.",
            tips: [
                "Select a paddock to auto-fill site-specific data",
                "Switch between Cane and Spur pruning modes",
                "Tap any field to highlight and override the value",
                "Final Yield (t/ha) and Block Yield shown in bold green"
            ]
        ),
        OnboardingPage(
            icon: "cloud.sun.rain.fill",
            iconColor: .teal,
            title: "Irrigation Recommendations",
            subtitle: "5-day forecast-driven runtimes",
            description: "Uses the next 5 days of ETo and rainfall, your block's application rate, crop coefficient, and efficiency to recommend irrigation hours. Each setting has a plain-English explanation below it.",
            tips: [
                "Site-specific fields are pre-filled from your block data",
                "See daily breakdown of crop use, rainfall, and deficit",
                "Tune replacement % for deficit irrigation strategies",
                "Final recommendation shown in hours and minutes"
            ]
        ),
        OnboardingPage(
            icon: "map.circle.fill",
            iconColor: .purple,
            title: "Vineyard Details Map",
            subtitle: "Filter pins and block info",
            description: "Toggle pin categories on and off, and choose which block details to display — area, vine totals, irrigation length, L/hr and more. All filters carry through to the full-screen map.",
            tips: [
                "Tick-box filters for each pin type",
                "Display filters for block area, vine totals, irrigation",
                "Filters available on full-screen map view",
                "Export pins and block data to PDF or XLS"
            ]
        ),
        OnboardingPage(
            icon: "person.2.fill",
            iconColor: .indigo,
            title: "Team, Roles & Categories",
            subtitle: "Manage users, roles and operator types",
            description: "Invite team members and assign both an access role and an operator category from Manage Vineyard. Pins and trips from the whole team appear across the vineyard, kept in sync via the cloud.",
            tips: [
                "Assign user roles to control tool access",
                "Link operator categories to each user",
                "All team members' pins visible across the vineyard",
                "Need help? Use the Support form in Settings"
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.smooth, value: currentPage)

            bottomBar
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 40)

                ZStack {
                    Circle()
                        .fill(page.iconColor.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Group {
                        if page.icon == "leaf.fill" {
                            GrapeLeafIcon(size: 42)
                        } else {
                            Image(systemName: page.icon)
                                .font(.system(size: 42))
                        }
                    }
                    .foregroundStyle(page.iconColor)
                }

                VStack(spacing: 8) {
                    Text(page.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(page.subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if !page.tips.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(page.tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(page.iconColor)
                                    .font(.body)
                                    .padding(.top, 1)
                                Text(tip)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }

                Spacer()
                    .frame(height: 20)
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.accentColor : Color(.tertiaryLabel))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.snappy, value: currentPage)
                }
            }

            if currentPage == pages.count - 1 {
                Button {
                    onComplete()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(.rect(cornerRadius: 14))
            } else {
                HStack {
                    Button("Skip") {
                        onComplete()
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation(.snappy) {
                            currentPage += 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
    }
}

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let tips: [String]
}
