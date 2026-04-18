import Foundation
import Supabase

nonisolated struct DailyGDDEntry: Codable, Sendable {
    let date: String
    let gdd: Double
}

nonisolated struct WeatherDailyGDDRecord: Codable, Sendable {
    let station_id: String
    let date: String
    let gdd: Double
    let temp_high: Double?
    let temp_low: Double?
    let base_temp: Double
    let updated_at: String?
}

@Observable
@MainActor
class DegreeDayService {
    var isLoading: Bool = false
    var errorMessage: String?
    var seasonGDD: Double?
    var lastUpdated: Date?
    var daysCovered: Int = 0
    var firstDateCovered: Date?
    var lastDateCovered: Date?

    private let apiKey: String = Config.EXPO_PUBLIC_WUNDERGROUND_API_KEY
    private let baseTemp: Double = 10.0

    private var cacheKey: String { "vinetrack_gdd_cache_v1" }
    private let lastDailySyncKey = "vinetrack_gdd_last_daily_sync"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let wuDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func loadCache() -> [String: [String: Double]] {
        (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [String: Double]]) ?? [:]
    }

    private func saveCache(_ cache: [String: [String: Double]]) {
        UserDefaults.standard.set(cache, forKey: cacheKey)
    }

    /// Returns true if today's daily refresh hasn't happened yet for this station.
    func needsDailyRefresh(for stationId: String) -> Bool {
        guard !stationId.isEmpty else { return false }
        let key = "\(lastDailySyncKey)_\(stationId)"
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    private func markDailyRefresh(for stationId: String) {
        let key = "\(lastDailySyncKey)_\(stationId)"
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func fetchSeasonGDD(stationId: String, seasonStart: Date) async {
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
            firstDateCovered = nil
            lastDateCovered = nil
            isLoading = false
            return
        }

        var cache = loadCache()
        var stationCache = cache[stationId] ?? [:]

        var dates: [Date] = []
        var d = start
        while d < today {
            dates.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? today
        }

        // 1. Pull existing records from Supabase for this station+season
        if isSupabaseConfigured {
            let startStr = Self.dateFormatter.string(from: start)
            let endStr = Self.dateFormatter.string(from: today)
            do {
                let records: [WeatherDailyGDDRecord] = try await supabase
                    .from("weather_daily_gdd")
                    .select()
                    .eq("station_id", value: stationId)
                    .gte("date", value: startStr)
                    .lt("date", value: endStr)
                    .execute()
                    .value
                for record in records {
                    let key = compactKey(fromISODate: record.date)
                    stationCache[key] = record.gdd
                }
            } catch {
                print("DegreeDayService: Supabase pull failed: \(error)")
            }
        }

        // 2. Determine missing dates and fetch them from Weather Underground
        let missingDates: [Date] = dates.filter { stationCache[Self.wuDateFormatter.string(from: $0)] == nil }
        let maxFetch = 120
        let toFetch = Array(missingDates.suffix(maxFetch))

        var newRecords: [WeatherDailyGDDRecord] = []
        if !apiKey.isEmpty {
            for date in toFetch {
                let dateStr = Self.wuDateFormatter.string(from: date)
                if let result = await fetchDailyGDD(stationId: stationId, dateString: dateStr) {
                    stationCache[dateStr] = result.gdd
                    newRecords.append(WeatherDailyGDDRecord(
                        station_id: stationId,
                        date: Self.dateFormatter.string(from: date),
                        gdd: result.gdd,
                        temp_high: result.high,
                        temp_low: result.low,
                        base_temp: baseTemp,
                        updated_at: nil
                    ))
                }
            }
        } else if missingDates.contains(where: { stationCache[Self.wuDateFormatter.string(from: $0)] == nil }) {
            errorMessage = "Weather Underground API key not configured."
        }

        // 3. Persist newly fetched records back to Supabase
        if isSupabaseConfigured && !newRecords.isEmpty {
            do {
                try await supabase
                    .from("weather_daily_gdd")
                    .upsert(newRecords, onConflict: "station_id,date")
                    .execute()
            } catch {
                print("DegreeDayService: Supabase upsert failed: \(error)")
            }
        }

        cache[stationId] = stationCache
        saveCache(cache)

        var total: Double = 0
        var count: Int = 0
        var firstCovered: Date?
        var lastCovered: Date?
        for date in dates {
            if let value = stationCache[Self.wuDateFormatter.string(from: date)] {
                total += value
                count += 1
                if firstCovered == nil { firstCovered = date }
                lastCovered = date
            }
        }

        seasonGDD = total
        daysCovered = count
        firstDateCovered = firstCovered
        lastDateCovered = lastCovered
        lastUpdated = Date()
        markDailyRefresh(for: stationId)
        isLoading = false
    }

    private func compactKey(fromISODate iso: String) -> String {
        // "2025-04-12" -> "20250412"
        iso.replacingOccurrences(of: "-", with: "")
    }

    private struct DailyResult {
        let gdd: Double
        let high: Double
        let low: Double
    }

    private func fetchDailyGDD(stationId: String, dateString: String) async -> DailyResult? {
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
            return DailyResult(gdd: gdd, high: high, low: low)
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
