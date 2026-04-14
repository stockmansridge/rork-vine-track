import Foundation

@MainActor
class TractorFuelLookupService {
    static let shared = TractorFuelLookupService()

    func lookupFuelUsage(brand: String, model: String) async -> Double? {
        let prompt = """
        What is the typical fuel consumption rate in litres per hour (L/hr) for a \(brand) \(model) tractor when the engine is under load?
        I need the figure for real field working conditions — for example, pulling a sprayer or implement through a vineyard at typical PTO operating RPM.
        Do NOT provide the idle or stationary fuel consumption. Provide the average consumption under moderate to heavy working load.
        Return ONLY a JSON object with no other text, in this exact format:
        {"fuelUsageLPerHour": 8.5}
        If you are unsure of the exact model, provide your best estimate for a similar tractor in that brand's lineup under working load.
        Return ONLY valid JSON, nothing else.
        """

        guard let responseText = try? await ToolkitHelper.sendChat(prompt: prompt) else { return nil }

        let cleaned = responseText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else { return nil }
        let result = try? JSONDecoder().decode(FuelLookupResponse.self, from: jsonData)
        if let result { return result.fuelUsageLPerHour }

        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let value = json["fuelUsageLPerHour"] as? Double {
            return value
        }

        let pattern = #"(\d+\.?\d*)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned),
           let value = Double(cleaned[range]) {
            return value
        }

        return nil
    }
}

nonisolated struct FuelLookupResponse: Codable, Sendable {
    let fuelUsageLPerHour: Double
}
