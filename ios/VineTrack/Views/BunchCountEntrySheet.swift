import SwiftUI

struct BunchCountEntrySheet: View {
    let site: SampleSite
    let onSave: (Double, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService
    @State private var bunchCountText: String = ""
    @State private var userName: String = ""
    @FocusState private var isCountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.purple)
                                .frame(width: 36, height: 36)
                            Text("\(site.siteIndex)")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Site #\(site.siteIndex)")
                                .font(.headline)
                            Text("\(site.paddockName) — Row \(site.rowNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sample Site")
                }

                Section {
                    TextField("Number of bunches", text: $bunchCountText)
                        .keyboardType(.decimalPad)
                        .focused($isCountFocused)
                } header: {
                    Text("Bunches Per Vine")
                } footer: {
                    Text("Count the number of bunches on this vine")
                }

                Section {
                    TextField("Your name", text: $userName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Recorded By")
                }

                Section {
                    LabeledContent("Date", value: Date.now, format: .dateTime.day().month().year().hour().minute())
                    LabeledContent("Latitude", value: String(format: "%.6f", site.latitude))
                    LabeledContent("Longitude", value: String(format: "%.6f", site.longitude))
                } header: {
                    Text("Details")
                }
            }
            .navigationTitle("Record Bunch Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let count = Double(bunchCountText), count >= 0 else { return }
                        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(count, name.isEmpty ? authService.userName : name)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(bunchCountText) == nil)
                }
            }
            .onAppear {
                userName = authService.userName
                if let existing = site.bunchCountEntry {
                    bunchCountText = String(format: "%.1f", existing.bunchesPerVine)
                    userName = existing.recordedBy
                }
                isCountFocused = true
            }
        }
    }
}
