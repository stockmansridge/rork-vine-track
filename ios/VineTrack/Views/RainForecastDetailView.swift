import SwiftUI

struct RainForecastDetailView: View {
    let latitude: Double
    let longitude: Double
    let windowDays: Int
    let thresholdMm: Double

    @Environment(\.dismiss) private var dismiss

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var days: [RainForecastDay] = []

    private var totalMm: Double {
        days.reduce(0) { $0 + $1.rainMm }
    }

    private var maxMm: Double {
        max(days.map(\.rainMm).max() ?? 0, 1)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && days.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading forecast…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load forecast", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        summarySection
                        dailySection
                    }
                }
            }
            .navigationTitle("Rain Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                if days.isEmpty { await load() }
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: "%.1f mm", totalMm))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(totalMm >= thresholdMm ? VineyardTheme.vineRed : VineyardTheme.leafGreen)
                    .monospacedDigit()
                Text("Total over next \(days.count) days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: totalMm >= thresholdMm ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(totalMm >= thresholdMm ? VineyardTheme.vineRed : VineyardTheme.leafGreen)
                    Text(String(format: "Threshold: %.0f mm", thresholdMm))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var dailySection: some View {
        Section("Daily Rainfall") {
            ForEach(days) { day in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(day.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(width: 70, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(day.rainMm >= 5 ? VineyardTheme.vineRed.opacity(0.8) : Color.blue.opacity(0.7))
                                .frame(width: geo.size.width * CGFloat(day.rainMm / maxMm))
                        }
                    }
                    .frame(height: 10)

                    Text(String(format: "%.1f mm", day.rainMm))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                        .foregroundStyle(day.rainMm > 0 ? .primary : .secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let requested = min(max(windowDays, 1), 16)
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=precipitation_sum&forecast_days=\(requested)&timezone=auto"

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid forecast URL."
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Failed to fetch forecast."
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [String: Any],
                  let times = daily["time"] as? [String],
                  let rainValues = daily["precipitation_sum"] as? [Any] else {
                errorMessage = "Forecast response could not be parsed."
                return
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current

            var parsed: [RainForecastDay] = []
            let count = min(times.count, rainValues.count)
            for i in 0..<count {
                guard let date = formatter.date(from: times[i]) else { continue }
                let mm = Self.parseDouble(rainValues[i]) ?? 0
                parsed.append(RainForecastDay(date: date, rainMm: mm))
            }
            days = parsed
        } catch {
            errorMessage = "Could not load forecast: \(error.localizedDescription)"
        }
    }

    private static func parseDouble(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

nonisolated struct RainForecastDay: Identifiable, Sendable, Hashable {
    let date: Date
    let rainMm: Double
    var id: Date { date }
}
