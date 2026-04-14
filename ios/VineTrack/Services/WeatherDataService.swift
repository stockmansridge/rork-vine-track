import Foundation
import CoreLocation

nonisolated struct WUObservation: Sendable {
    let temperature: Double?
    let windSpeed: Double?
    let windDirection: String?
    let humidity: Double?
    let stationID: String
}

@Observable
class WeatherDataService {
    var isLoading: Bool = false
    var errorMessage: String?
    var lastObservation: WUObservation?

    private let apiKey: String = Config.EXPO_PUBLIC_WUNDERGROUND_API_KEY

    func fetchCurrentConditions(stationId: String) async {
        guard !apiKey.isEmpty else {
            errorMessage = "Weather Underground API key not configured."
            return
        }
        guard !stationId.isEmpty else {
            errorMessage = "No weather station ID provided."
            return
        }

        isLoading = true
        errorMessage = nil
        lastObservation = nil

        let urlString = "https://api.weather.com/v2/pws/observations/current?stationId=\(stationId)&format=json&units=m&numericPrecision=decimal&apiKey=\(apiKey)"

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid request URL."
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response from Weather Underground."
                isLoading = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 204 {
                    errorMessage = "No recent data from station \(stationId). The station may be offline."
                } else if httpResponse.statusCode == 401 {
                    errorMessage = "Invalid API key. Check your Weather Underground API key."
                } else {
                    errorMessage = "Failed to fetch weather data (HTTP \(httpResponse.statusCode))."
                }
                isLoading = false
                return
            }

            let observation = try Self.parseObservations(data)
            lastObservation = observation
        } catch {
            errorMessage = "Could not load weather data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func fetchForStationOrNearest(stationId: String?, location: CLLocation?) async {
        if let stationId, !stationId.isEmpty {
            await fetchCurrentConditions(stationId: stationId)
        } else if let location {
            await fetchNearestAndGetConditions(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        } else {
            errorMessage = "No station ID set and location unavailable."
        }
    }

    private func fetchNearestAndGetConditions(latitude: Double, longitude: Double) async {
        guard !apiKey.isEmpty else {
            errorMessage = "Weather Underground API key not configured."
            return
        }

        isLoading = true
        errorMessage = nil

        let geocode = "\(latitude),\(longitude)"
        let urlString = "https://api.weather.com/v3/location/near?geocode=\(geocode)&product=pws&format=json&apiKey=\(apiKey)"

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid request URL."
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                errorMessage = "Could not find nearby stations."
                isLoading = false
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let locationDict = json["location"] as? [String: Any],
                  let stationIds = locationDict["stationId"] as? [String],
                  let firstStation = stationIds.first else {
                errorMessage = "No nearby weather stations found."
                isLoading = false
                return
            }

            isLoading = false
            await fetchCurrentConditions(stationId: firstStation)
        } catch {
            errorMessage = "Could not find nearby stations: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private static func parseObservations(_ data: Data) throws -> WUObservation {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let observations = json["observations"] as? [[String: Any]],
              let obs = observations.first else {
            throw URLError(.cannotParseResponse)
        }

        let stationID = obs["stationID"] as? String ?? ""

        var temperature: Double?
        var windSpeed: Double?
        var humidity: Double?
        var winddir: Int?

        if let metric = obs["metric"] as? [String: Any] {
            temperature = parseDouble(metric["temp"])
            windSpeed = parseDouble(metric["windSpeed"])
        }

        humidity = parseDouble(obs["humidity"])
        winddir = obs["winddir"] as? Int

        let windDirection: String? = winddir.map { Self.degreesToCardinal($0) }

        return WUObservation(
            temperature: temperature,
            windSpeed: windSpeed,
            windDirection: windDirection,
            humidity: humidity,
            stationID: stationID
        )
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func degreesToCardinal(_ degrees: Int) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((Double(degrees) + 11.25) / 22.5) % 16
        return directions[index]
    }
}
