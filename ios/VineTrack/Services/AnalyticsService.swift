import Foundation
import Supabase

nonisolated struct AnalyticsEvent: Codable, Sendable {
    let id: String
    let user_id: String?
    let vineyard_id: String?
    let event_name: String
    let event_data: String?
    let created_at: String
}

@Observable
@MainActor
class AnalyticsService {
    private var userId: String?
    private var vineyardId: UUID?
    private var pendingEvents: [AnalyticsEvent] = []
    private var flushTask: Task<Void, Never>?

    var isConfigured: Bool { isSupabaseConfigured }

    func setUser(_ id: String?) {
        userId = id
    }

    func setVineyard(_ id: UUID?) {
        vineyardId = id
    }

    func track(_ eventName: String, data: [String: String]? = nil) {
        guard isConfigured else { return }
        var eventDataString: String?
        if let data {
            if let jsonData = try? JSONEncoder().encode(data) {
                eventDataString = String(data: jsonData, encoding: .utf8)
            }
        }

        let event = AnalyticsEvent(
            id: UUID().uuidString,
            user_id: userId,
            vineyard_id: vineyardId?.uuidString,
            event_name: eventName,
            event_data: eventDataString,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        pendingEvents.append(event)
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    func flush() async {
        guard !pendingEvents.isEmpty else { return }
        let eventsToSend = pendingEvents
        pendingEvents = []

        do {
            try await supabase.from("analytics_events")
                .insert(eventsToSend)
                .execute()
        } catch {
            pendingEvents.insert(contentsOf: eventsToSend, at: 0)
        }
    }
}
