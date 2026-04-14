import CoreLocation

extension Array where Element == CoordinatePoint {
    var centroid: CLLocationCoordinate2D {
        guard !isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let totalLat = reduce(0.0) { $0 + $1.latitude }
        let totalLon = reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(
            latitude: totalLat / Double(count),
            longitude: totalLon / Double(count)
        )
    }
}
