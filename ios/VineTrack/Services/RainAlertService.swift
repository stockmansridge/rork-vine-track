import Foundation
import UserNotifications
import BackgroundTasks

@Observable
class RainAlertService {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var lastCheckDate: Date?
    var lastForecastTotalMm: Double?
    var lastForecastDayCount: Int = 0
    var lastError: String?
    var isChecking: Bool = false

    private let notificationId = "vinetrack.rain.forecast.alert"
    private let irrigationNotificationId = "vinetrack.irrigation.forecast.alert"
    static let backgroundTaskIdentifier = "app.rork.nt0v48tayl7v8noxcfe74.rainAlertCheck"

    private let lastCheckDateKey = "vinetrack.rain.alert.lastCheckDate"
    private let lastForecastTotalKey = "vinetrack.rain.alert.lastForecastTotal"
    private let lastForecastDaysKey = "vinetrack.rain.alert.lastForecastDays"
    private let lastIrrigationHoursKey = "vinetrack.irrigation.alert.lastHoursByPaddock"
    private let lastIrrigationCheckDateKey = "vinetrack.irrigation.alert.lastCheckDate"

    var lastIrrigationCheckDate: Date?
    var lastIrrigationHoursByPaddock: [String: Double] = [:]
    var lastIrrigationChangeSummary: String?

    init() {
        if let saved = UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date {
            lastCheckDate = saved
        }
        let total = UserDefaults.standard.double(forKey: lastForecastTotalKey)
        if total > 0 { lastForecastTotalMm = total }
        lastForecastDayCount = UserDefaults.standard.integer(forKey: lastForecastDaysKey)
        if let saved = UserDefaults.standard.object(forKey: lastIrrigationCheckDateKey) as? Date {
            lastIrrigationCheckDate = saved
        }
        if let dict = UserDefaults.standard.dictionary(forKey: lastIrrigationHoursKey) as? [String: Double] {
            lastIrrigationHoursByPaddock = dict
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func checkForecastAndNotify(
        latitude: Double,
        longitude: Double,
        windowDays: Int,
        thresholdMm: Double
    ) async {
        isChecking = true
        defer { isChecking = false }
        lastError = nil

        let requestedDays = min(max(windowDays, 1), 16)
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=precipitation_sum&forecast_days=\(requestedDays)&timezone=auto"
        guard let url = URL(string: urlString) else {
            lastError = "Invalid forecast URL."
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastError = "Failed to fetch forecast."
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [String: Any],
                  let rainValues = daily["precipitation_sum"] as? [Any] else {
                lastError = "Forecast response could not be parsed."
                return
            }

            let mmValues: [Double] = rainValues.compactMap { value in
                if let d = value as? Double { return d }
                if let i = value as? Int { return Double(i) }
                if let n = value as? NSNumber { return n.doubleValue }
                if let s = value as? String { return Double(s) }
                return nil
            }

            let total = mmValues.reduce(0, +)
            lastCheckDate = Date()
            lastForecastTotalMm = total
            lastForecastDayCount = mmValues.count

            UserDefaults.standard.set(lastCheckDate, forKey: lastCheckDateKey)
            UserDefaults.standard.set(total, forKey: lastForecastTotalKey)
            UserDefaults.standard.set(mmValues.count, forKey: lastForecastDaysKey)

            if total >= thresholdMm {
                await scheduleNotification(totalMm: total, days: mmValues.count, thresholdMm: thresholdMm, windowDays: windowDays)
            } else {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
            }
        } catch {
            lastError = "Could not load forecast: \(error.localizedDescription)"
        }
    }

    private func scheduleNotification(totalMm: Double, days: Int, thresholdMm: Double, windowDays: Int) async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rain Forecast Alert"
        let window = min(windowDays, days)
        content.body = String(
            format: "%.1f mm of rain forecast over the next %d days (threshold %.0f mm). Consider adjusting irrigation.",
            totalMm, window, thresholdMm
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
    }

    // MARK: - Background Task Scheduling

    /// Register the background task handler. Call this in App init before the app finishes launching.
    nonisolated static func registerBackgroundTask(handler: @escaping @Sendable (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handler(refreshTask)
        }
    }

    /// Schedule the next daily background refresh for the next 9am local time.
    /// iOS may run the task slightly later depending on system conditions.
    func scheduleDailyBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Self.nextNineAMLocal()
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            lastError = "Could not schedule background check: \(error.localizedDescription)"
        }
    }

    /// Returns the next occurrence of 9:00 AM in the device's local time zone.
    nonisolated static func nextNineAMLocal() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        components.second = 0
        let todayNine = calendar.date(from: components) ?? now
        if todayNine > now {
            return todayNine
        }
        return calendar.date(byAdding: .day, value: 1, to: todayNine) ?? todayNine.addingTimeInterval(24 * 3600)
    }

    // MARK: - Irrigation Forecast Alert

    /// Fetch the 5-day forecast, compute irrigation recommendations for each
    /// paddock with a known application rate, and notify if any value has changed
    /// since the last check.
    func checkIrrigationAndNotify(
        latitude: Double,
        longitude: Double,
        paddocks: [Paddock],
        settings: AppSettings
    ) async {
        guard !paddocks.isEmpty else { return }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=et0_fao_evapotranspiration,precipitation_sum&forecast_days=5&timezone=auto"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [String: Any],
                  let times = daily["time"] as? [String],
                  let etoValues = daily["et0_fao_evapotranspiration"] as? [Any],
                  let rainValues = daily["precipitation_sum"] as? [Any] else {
                return
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current

            var days: [ForecastDay] = []
            let count = min(times.count, min(etoValues.count, rainValues.count))
            for i in 0..<count {
                guard let date = formatter.date(from: times[i]) else { continue }
                let eto = Self.parseDouble(etoValues[i]) ?? 0
                let rain = Self.parseDouble(rainValues[i]) ?? 0
                days.append(ForecastDay(date: date, forecastEToMm: eto, forecastRainMm: rain))
            }
            guard !days.isEmpty else { return }

            let irrSettings = IrrigationSettings(
                irrigationApplicationRateMmPerHour: 0,
                cropCoefficientKc: settings.irrigationKc,
                irrigationEfficiencyPercent: settings.irrigationEfficiencyPercent,
                rainfallEffectivenessPercent: settings.irrigationRainfallEffectivenessPercent,
                replacementPercent: settings.irrigationReplacementPercent,
                soilMoistureBufferMm: settings.irrigationSoilBufferMm
            )

            let targetPaddocks: [Paddock]
            if let pid = settings.irrigationAlertPaddockId,
               let one = paddocks.first(where: { $0.id == pid && ($0.mmPerHour ?? 0) > 0 }) {
                targetPaddocks = [one]
            } else {
                targetPaddocks = paddocks.filter { ($0.mmPerHour ?? 0) > 0 }
            }
            guard !targetPaddocks.isEmpty else { return }

            var newHoursByPaddock: [String: Double] = [:]
            var changes: [(name: String, old: Double?, new: Double)] = []

            for paddock in targetPaddocks {
                guard let mmHr = paddock.mmPerHour, mmHr > 0 else { continue }
                var perPaddock = irrSettings
                perPaddock.irrigationApplicationRateMmPerHour = mmHr
                guard let result = IrrigationCalculator.calculate(forecastDays: days, settings: perPaddock) else { continue }
                let key = paddock.id.uuidString
                let rounded = (result.recommendedIrrigationHours * 10).rounded() / 10
                newHoursByPaddock[key] = rounded
                let previous = lastIrrigationHoursByPaddock[key]
                if previous == nil || abs((previous ?? 0) - rounded) >= 0.1 {
                    changes.append((name: paddock.name, old: previous, new: rounded))
                }
            }

            lastIrrigationCheckDate = Date()
            lastIrrigationHoursByPaddock = newHoursByPaddock
            UserDefaults.standard.set(lastIrrigationCheckDate, forKey: lastIrrigationCheckDateKey)
            UserDefaults.standard.set(newHoursByPaddock, forKey: lastIrrigationHoursKey)

            if !changes.isEmpty {
                let summary = changes.prefix(3).map { change -> String in
                    if let old = change.old {
                        return String(format: "%@: %.1f → %.1f hr", change.name, old, change.new)
                    }
                    return String(format: "%@: %.1f hr", change.name, change.new)
                }.joined(separator: ", ")
                let body: String
                if changes.count > 3 {
                    body = "\(summary) +\(changes.count - 3) more. Open VineTrack for details."
                } else {
                    body = "\(summary). Open VineTrack for details."
                }
                lastIrrigationChangeSummary = body
                await scheduleIrrigationNotification(body: body)
            } else {
                lastIrrigationChangeSummary = nil
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [irrigationNotificationId])
            }
        } catch {
            // silent on background failures
        }
    }

    private func scheduleIrrigationNotification(body: String) async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Irrigation Forecast Updated"
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: irrigationNotificationId, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    nonisolated private static func parseDouble(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    func cancelScheduledBackgroundCheck() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
    }
}
