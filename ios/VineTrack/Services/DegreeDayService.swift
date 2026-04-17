import Foundation

nonisolated struct DailyGDDEntry: Codable, Sendable {
    let date: String
    let gdd: Double
}

@Observable
class DegreeDayService {
    var isLoading: Bool = false
    var errorMessage: String?
    var seasonGDD: Double?
    var lastUpdated: Date?
    var daysCovered: Int = 0

    private let apiKey: String = Config.EXPO_PUBLIC_WUNDERGROUND_API_KEY
    private let baseTemp: Double = 10.0

    private var cacheKey: String {
        "vinetrack_gdd_cache_v1"
    }

    private func loadCache() -> [String: [String: Double]] {
        (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [String: Double]]) ?? [:]
    }

    private func saveCache(_ cache: [String: [String: Double]]) {
        UserDefaults.standard.set(cache, forKey: cacheKey)
    }

    func fetchSeasonGDD(stationId: String, seasonStart: Date) async {
        guard !apiKey.isEmpty else {
            errorMessage = "Weather Underground API key not configured."
            return
        }
        guard !stationId.isEmpty else {
            errorMessage = "No weather station set. Configure one in Vineyard Setup."
            return
        }

        isLoading = true
        errorMessage = nil

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: seasonStart)
        guard start <= today else {
            seasonGDD = 0
            daysCovered = 0
            lastUpdated = Date()
            isLoading = false
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var cache = loadCache()
        var stationCache = cache[stationId] ?? [:]

        var dates: [Date] = []
        var d = start
        while d < today {
            dates.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? today
        }

        let missingDates: [Date] = dates.filter { stationCache[formatter.string(from: $0)] == nil }

        let maxFetch = 120
        let toFetch = Array(missingDates.suffix(maxFetch))

        for date in toFetch {
            let dateStr = formatter.string(from: date)
            if let gdd = await fetchDailyGDD(stationId: stationId, dateString: dateStr) {
                stationCache[dateStr] = gdd
            }
        }

        cache[stationId] = stationCache
        saveCache(cache)

        var total: Double = 0
        var count: Int = 0
        for date in dates {
            if let value = stationCache[formatter.string(from: date)] {
                total += value
                count += 1
            }
        }

        seasonGDD = total
        daysCovered = count
        lastUpdated = Date()
        isLoading = false
    }

    private func fetchDailyGDD(stationId: String, dateString: String) async -> Double? {
        let urlString = "https://api.weather.com/v2/pws/history/daily?stationId=\(stationId)&format=json&units=m&date=\(dateString)&numericPrecision=decimal&apiKey=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let summaries = json["summaries"] as? [[String: Any]],
                  let obs = summaries.first,
                  let metric = obs["metric"] as? [String: Any] else {
                return nil
            }

            let tempHigh = parseDouble(metric["tempHigh"])
            let tempLow = parseDouble(metric["tempLow"])
            guard let high = tempHigh, let low = tempLow else { return nil }
            let avg = (high + low) / 2.0
            let gdd = max(0, avg - baseTemp)
            return gdd
        } catch {
            return nil
        }
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
