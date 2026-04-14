import Foundation
import CoreLocation

nonisolated struct NearbyPWSResponse: Sendable {
    let location: PWSLocationWrapper?
}

nonisolated struct PWSLocationWrapper: Sendable {
    let stationId: [String]
    let stationName: [String]
    let distanceKm: [Double]
    let distanceMi: [Double]
    let latitude: [Double]
    let longitude: [Double]
}

struct NearbyStation: Identifiable, Sendable {
    let id: String
    let name: String
    let distanceKm: Double
    let distanceMi: Double
    let latitude: Double
    let longitude: Double

    var localizedDistance: String {
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            return String(format: "%.1f km", distanceKm)
        } else {
            return String(format: "%.1f mi", distanceMi)
        }
    }
}

@Observable
class WeatherStationService {
    var nearbyStations: [NearbyStation] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let apiKey: String = Config.EXPO_PUBLIC_WUNDERGROUND_API_KEY

    func fetchNearbyStations(latitude: Double, longitude: Double) async {
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
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                errorMessage = "Failed to fetch nearby stations (HTTP \(code))."
                isLoading = false
                return
            }

            let parsed = try Self.parseResponse(data)

            guard let loc = parsed.location else {
                nearbyStations = []
                isLoading = false
                return
            }

            var stations: [NearbyStation] = []
            for i in 0..<loc.stationId.count {
                stations.append(NearbyStation(
                    id: loc.stationId[i],
                    name: i < loc.stationName.count ? loc.stationName[i] : loc.stationId[i],
                    distanceKm: i < loc.distanceKm.count ? loc.distanceKm[i] : 0,
                    distanceMi: i < loc.distanceMi.count ? loc.distanceMi[i] : 0,
                    latitude: i < loc.latitude.count ? loc.latitude[i] : 0,
                    longitude: i < loc.longitude.count ? loc.longitude[i] : 0
                ))
            }

            nearbyStations = stations
        } catch {
            errorMessage = "Could not load stations: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private static func parseResponse(_ data: Data) throws -> NearbyPWSResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locationDict = json["location"] as? [String: Any] else {
            return NearbyPWSResponse(location: nil)
        }

        let stationIds = locationDict["stationId"] as? [String] ?? []
        let stationNames = locationDict["stationName"] as? [String] ?? []

        let distanceKm = Self.parseDoubleArray(locationDict["distanceKm"])
        let distanceMi = Self.parseDoubleArray(locationDict["distanceMi"])
        let latitude = Self.parseDoubleArray(locationDict["latitude"])
        let longitude = Self.parseDoubleArray(locationDict["longitude"])

        let wrapper = PWSLocationWrapper(
            stationId: stationIds,
            stationName: stationNames,
            distanceKm: distanceKm,
            distanceMi: distanceMi,
            latitude: latitude,
            longitude: longitude
        )
        return NearbyPWSResponse(location: wrapper)
    }

    private static func parseDoubleArray(_ value: Any?) -> [Double] {
        if let doubles = value as? [Double] { return doubles }
        if let ints = value as? [Int] { return ints.map { Double($0) } }
        if let numbers = value as? [NSNumber] { return numbers.map { $0.doubleValue } }
        if let strings = value as? [String] { return strings.compactMap { Double($0) } }
        if let mixed = value as? [Any] {
            return mixed.compactMap { item -> Double? in
                if let d = item as? Double { return d }
                if let i = item as? Int { return Double(i) }
                if let n = item as? NSNumber { return n.doubleValue }
                if let s = item as? String { return Double(s) }
                return nil
            }
        }
        return []
    }
}
