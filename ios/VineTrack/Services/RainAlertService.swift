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
    static let backgroundTaskIdentifier = "app.rork.nt0v48tayl7v8noxcfe74.rainAlertCheck"

    private let lastCheckDateKey = "vinetrack.rain.alert.lastCheckDate"
    private let lastForecastTotalKey = "vinetrack.rain.alert.lastForecastTotal"
    private let lastForecastDaysKey = "vinetrack.rain.alert.lastForecastDays"

    init() {
        if let saved = UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date {
            lastCheckDate = saved
        }
        let total = UserDefaults.standard.double(forKey: lastForecastTotalKey)
        if total > 0 { lastForecastTotalMm = total }
        lastForecastDayCount = UserDefaults.standard.integer(forKey: lastForecastDaysKey)
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

    /// Schedule the next daily background refresh (iOS decides the exact time).
    func scheduleDailyBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Earliest 6 hours from now — iOS will typically run once per day.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            lastError = "Could not schedule background check: \(error.localizedDescription)"
        }
    }

    func cancelScheduledBackgroundCheck() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
    }
}
