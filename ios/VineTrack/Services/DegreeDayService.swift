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

nonisolated struct DailyTemp: Codable, Sendable {
    let high: Double
    let low: Double
}

nonisolated struct GDDComputeResult: Sendable {
    let gdd: Double
    let daysCovered: Int
    let firstDate: Date?
    let lastDate: Date?
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
    var lastDiagnostics: String?
    var lastStationId: String?
    var lastSeasonStart: Date?
    var lastFetchAttempted: Int = 0
    var lastFetchSucceeded: Int = 0
    var lastFetchStatusSample: String?

    /// Per-station cache of daily temperatures keyed by yyyyMMdd.
    private var temps: [String: [String: DailyTemp]] = [:]

    private let apiKey: String = Config.EXPO_PUBLIC_WUNDERGROUND_API_KEY
    private let baseTemp: Double = 10.0
    private let beddCap: Double = 19.0

    private var cacheKey: String { "vinetrack_gdd_temps_cache_v2" }
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

    init() {
        loadCache()
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: [String: DailyTemp]].self, from: data) {
            temps = decoded
        }
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(temps) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
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

    /// Fetch & cache temperatures for the given station from `seasonStart` through yesterday.
    /// Sets the published `seasonGDD` using the supplied latitude / BEDD flag.
    func fetchSeasonGDD(stationId: String, seasonStart: Date, latitude: Double? = nil, useBEDD: Bool = true) async {
        guard !stationId.isEmpty else {
            errorMessage = "No weather station set. Configure one in Vineyard Setup."
            return
        }

        isLoading = true
        errorMessage = nil
        lastStationId = stationId
        lastSeasonStart = seasonStart
        lastFetchAttempted = 0
        lastFetchSucceeded = 0
        lastFetchStatusSample = nil
        var diagnostics: [String] = []
        if apiKey.isEmpty {
            diagnostics.append("Weather Underground API key missing in build.")
        } else {
            diagnostics.append("API key: \(String(apiKey.prefix(4)))… (\(apiKey.count) chars)")
        }

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

        var stationTemps = temps[stationId] ?? [:]

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
                    if let high = record.temp_high, let low = record.temp_low {
                        stationTemps[key] = DailyTemp(high: high, low: low)
                    }
                }
                diagnostics.append("Supabase cached rows: \(records.count)")
            } catch {
                diagnostics.append("Supabase pull failed: \(error.localizedDescription)")
                print("DegreeDayService: Supabase pull failed: \(error)")
            }
        } else {
            diagnostics.append("Supabase not configured.")
        }

        // 2. Determine missing dates and fetch from Weather Underground
        let missingDates: [Date] = dates.filter { stationTemps[Self.wuDateFormatter.string(from: $0)] == nil }
        let maxFetch = 200
        let toFetch = Array(missingDates.suffix(maxFetch))
        diagnostics.append("Season dates: \(dates.count) • missing: \(missingDates.count) • will fetch: \(toFetch.count)")

        var newRecords: [WeatherDailyGDDRecord] = []
        var firstStatusSample: String?
        if !apiKey.isEmpty {
            for date in toFetch {
                let dateStr = Self.wuDateFormatter.string(from: date)
                lastFetchAttempted += 1
                let outcome = await fetchDailyTemps(stationId: stationId, dateString: dateStr)
                if firstStatusSample == nil {
                    firstStatusSample = outcome.statusDescription
                }
                if let result = outcome.result {
                    lastFetchSucceeded += 1
                    stationTemps[dateStr] = DailyTemp(high: result.high, low: result.low)
                    let plainGDD = max(0, ((result.high + result.low) / 2.0) - baseTemp)
                    newRecords.append(WeatherDailyGDDRecord(
                        station_id: stationId,
                        date: Self.dateFormatter.string(from: date),
                        gdd: plainGDD,
                        temp_high: result.high,
                        temp_low: result.low,
                        base_temp: baseTemp,
                        updated_at: nil
                    ))
                }
            }
            lastFetchStatusSample = firstStatusSample
            if lastFetchAttempted > 0 {
                diagnostics.append("WU fetches: \(lastFetchSucceeded)/\(lastFetchAttempted) succeeded")
                if lastFetchSucceeded == 0, let sample = firstStatusSample {
                    diagnostics.append("WU sample: \(sample)")
                    errorMessage = "Weather Underground request failed: \(sample). Check station ID."
                }
            }
        } else if !missingDates.isEmpty {
            errorMessage = "Weather Underground API key not configured."
        }

        // 3. Persist to Supabase
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

        temps[stationId] = stationTemps
        saveCache()

        let result = computeGDD(stationId: stationId, from: start, to: today, latitude: latitude, useBEDD: useBEDD)
        seasonGDD = result.gdd
        daysCovered = result.daysCovered
        firstDateCovered = result.firstDate
        lastDateCovered = result.lastDate
        lastUpdated = Date()
        if result.daysCovered == 0 && errorMessage == nil {
            if apiKey.isEmpty {
                errorMessage = "Weather Underground API key not configured."
            } else if dates.isEmpty {
                errorMessage = "Budburst date is today — no days to accumulate yet."
            } else {
                errorMessage = "No temperature data returned for station \"\(stationId)\". Verify the PWS ID is correct and reporting."
            }
        }
        diagnostics.append("Days with data: \(result.daysCovered) • GDD: \(Int(result.gdd))")
        lastDiagnostics = diagnostics.joined(separator: "\n")
        markDailyRefresh(for: stationId)
        isLoading = false
    }

    /// Compute GDD/BEDD from cached temperatures between two dates (exclusive end).
    func computeGDD(stationId: String, from start: Date, to end: Date, latitude: Double?, useBEDD: Bool) -> GDDComputeResult {
        guard let stationTemps = temps[stationId] else {
            return GDDComputeResult(gdd: 0, daysCovered: 0, firstDate: nil, lastDate: nil)
        }
        let cal = Calendar.current
        var total: Double = 0
        var count: Int = 0
        var first: Date?
        var last: Date?
        var d = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        while d < endDay {
            let key = Self.wuDateFormatter.string(from: d)
            if let temp = stationTemps[key] {
                let value = useBEDD ? beddDay(high: temp.high, low: temp.low, latitude: latitude, date: d)
                                    : max(0, ((temp.high + temp.low) / 2.0) - baseTemp)
                total += value
                count += 1
                if first == nil { first = d }
                last = d
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? endDay
        }
        return GDDComputeResult(gdd: total, daysCovered: count, firstDate: first, lastDate: last)
    }

    private func beddDay(high: Double, low: Double, latitude: Double?, date: Date) -> Double {
        let cappedHigh = min(high, beddCap)
        let cappedLow = min(low, beddCap)
        let mean = (cappedHigh + cappedLow) / 2.0
        var heat = max(0, mean - baseTemp)

        let range = high - low
        if range > 13 {
            heat += (range - 13) * 0.25
        }

        let k = dayLengthFactor(latitude: latitude, date: date)
        return heat * k
    }

    private func dayLengthFactor(latitude: Double?, date: Date) -> Double {
        guard let lat = latitude, abs(lat) <= 66 else { return 1.0 }
        let cal = Calendar(identifier: .gregorian)
        let n = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        let decl = 23.45 * sin((360.0 * Double(284 + n) / 365.0) * .pi / 180.0)
        let latRad = lat * .pi / 180.0
        let declRad = decl * .pi / 180.0
        let cosOmega = -tan(latRad) * tan(declRad)
        let clamped = max(-1.0, min(1.0, cosOmega))
        let omega = acos(clamped) * 180.0 / .pi
        let dayLength = 2.0 * omega / 15.0
        return max(0.5, min(1.5, dayLength / 12.0))
    }

    private func compactKey(fromISODate iso: String) -> String {
        iso.replacingOccurrences(of: "-", with: "")
    }

    private struct DailyTempResult {
        let high: Double
        let low: Double
    }

    private struct FetchOutcome {
        let result: DailyTempResult?
        let statusDescription: String
    }

    private func fetchDailyTemps(stationId: String, dateString: String) async -> FetchOutcome {
        let urlString = "https://api.weather.com/v2/pws/history/daily?stationId=\(stationId)&format=json&units=m&date=\(dateString)&numericPrecision=decimal&apiKey=\(apiKey)"
        guard let url = URL(string: urlString) else {
            return FetchOutcome(result: nil, statusDescription: "Invalid URL")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                return FetchOutcome(result: nil, statusDescription: "No HTTP response")
            }
            if http.statusCode != 200 {
                let body = String(data: data.prefix(120), encoding: .utf8) ?? ""
                return FetchOutcome(result: nil, statusDescription: "HTTP \(http.statusCode) \(body)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return FetchOutcome(result: nil, statusDescription: "Bad JSON")
            }
            let entries = (json["observations"] as? [[String: Any]])
                ?? (json["summaries"] as? [[String: Any]])
                ?? []
            guard let obs = entries.first else {
                let keys = json.keys.sorted().joined(separator: ",")
                return FetchOutcome(result: nil, statusDescription: "Empty response (keys: \(keys))")
            }
            let metric = (obs["metric"] as? [String: Any]) ?? obs
            let tempHigh = parseDouble(metric["tempHigh"]) ?? parseDouble(metric["tempMax"]) ?? parseDouble(obs["tempHigh"])
            let tempLow = parseDouble(metric["tempLow"]) ?? parseDouble(metric["tempMin"]) ?? parseDouble(obs["tempLow"])
            guard let high = tempHigh, let low = tempLow else {
                return FetchOutcome(result: nil, statusDescription: "Missing tempHigh/tempLow")
            }
            return FetchOutcome(result: DailyTempResult(high: high, low: low), statusDescription: "200 OK")
        } catch {
            return FetchOutcome(result: nil, statusDescription: "Network error: \(error.localizedDescription)")
        }
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
