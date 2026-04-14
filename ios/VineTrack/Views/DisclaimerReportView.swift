import SwiftUI
import UniformTypeIdentifiers

struct DisclaimerReportView: View {
    @Environment(AdminService.self) private var adminService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessControl) private var accessControl
    @State private var searchText: String = ""
    @State private var isExporting: Bool = false
    @State private var csvFile: DisclaimerCSVFile?

    private var filteredAcceptances: [DisclaimerAcceptance] {
        if searchText.isEmpty { return adminService.disclaimerAcceptances }
        return adminService.disclaimerAcceptances.filter {
            $0.user_name.localizedCaseInsensitiveContains(searchText) ||
            $0.user_email.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(VineyardTheme.leafGreen)
                            .frame(width: 44, height: 44)
                            .background(VineyardTheme.leafGreen.opacity(0.12), in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(adminService.disclaimerAcceptances.count)")
                                .font(.title.weight(.bold))
                            Text("Total Acceptances")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if adminService.isLoadingDisclaimers {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading...")
                            Spacer()
                        }
                    }
                } else if filteredAcceptances.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(searchText.isEmpty ? "No acceptances yet" : "No results")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section("\(filteredAcceptances.count) record\(filteredAcceptances.count == 1 ? "" : "s")") {
                        ForEach(filteredAcceptances) { acceptance in
                            DisclaimerAcceptanceRow(acceptance: acceptance)
                        }
                    }
                }
            }
            .navigationTitle("Disclaimer Report")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search by name or email...")
            .refreshable {
                await adminService.fetchDisclaimerAcceptances()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if accessControl?.canExport ?? true {
                        Button {
                            exportCSV()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(adminService.disclaimerAcceptances.isEmpty)
                    }
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: csvFile,
                contentType: .commaSeparatedText,
                defaultFilename: "disclaimer_acceptances_\(exportDateString).csv"
            ) { _ in
                csvFile = nil
            }
            .task {
                if adminService.disclaimerAcceptances.isEmpty {
                    await adminService.fetchDisclaimerAcceptances()
                }
            }
        }
    }

    private var exportDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func exportCSV() {
        var csv = "Name,Email,Date Accepted,Time Accepted\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium

        for acceptance in adminService.disclaimerAcceptances {
            let name = acceptance.user_name.replacingOccurrences(of: ",", with: " ")
            let email = acceptance.user_email
            let dateStr: String
            let timeStr: String
            if let date = acceptance.acceptedDate {
                dateStr = dateFormatter.string(from: date)
                timeStr = timeFormatter.string(from: date)
            } else {
                dateStr = acceptance.accepted_at
                timeStr = ""
            }
            csv += "\"\(name)\",\"\(email)\",\"\(dateStr)\",\"\(timeStr)\"\n"
        }

        csvFile = DisclaimerCSVFile(csvString: csv)
        isExporting = true
    }
}

struct DisclaimerAcceptanceRow: View {
    let acceptance: DisclaimerAcceptance

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(VineyardTheme.leafGreen.gradient)
                    .frame(width: 36, height: 36)
                Text(acceptance.user_name.prefix(1).uppercased())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(acceptance.user_name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(acceptance.user_email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let date = acceptance.acceptedDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct DisclaimerCSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let csvString: String

    init(csvString: String) {
        self.csvString = csvString
    }

    init(configuration: ReadConfiguration) throws {
        csvString = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csvString.utf8))
    }
}
