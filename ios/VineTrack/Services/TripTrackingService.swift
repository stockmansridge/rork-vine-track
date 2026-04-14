import Foundation
import CoreLocation

@Observable
@MainActor
class TripTrackingService {
    var isTracking: Bool = false
    
    private var trackingTask: Task<Void, Never>?
    private weak var store: DataStore?
    private weak var locationService: LocationService?

    func configure(store: DataStore, locationService: LocationService) {
        self.store = store
        self.locationService = locationService
        resumeIfNeeded()
    }

    func startTracking() {
        guard let locationService else { return }
        isTracking = true
        locationService.startBackgroundUpdating()
        guard trackingTask == nil else { return }
        let interval = store?.settings.rowTrackingInterval ?? 1.0
        trackingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                guard let locationService = self.locationService,
                      let store = self.store,
                      let location = locationService.location else { continue }
                guard var currentTrip = store.activeTrip else {
                    self.stopTracking()
                    break
                }

                let newPoint = CoordinatePoint(coordinate: location.coordinate)

                if let lastPoint = currentTrip.pathPoints.last {
                    let lastLocation = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
                    let newLocation = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    let segmentDistance = newLocation.distance(from: lastLocation)
                    if segmentDistance > 1 {
                        currentTrip.totalDistance += segmentDistance
                        currentTrip.pathPoints.append(newPoint)
                        store.updateTrip(currentTrip)
                    }
                } else {
                    currentTrip.pathPoints.append(newPoint)
                    store.updateTrip(currentTrip)
                }
            }
        }
    }

    func pauseTracking() {
        guard isTracking, let store, var trip = store.activeTrip, !trip.isPaused else { return }
        trip.isPaused = true
        trip.pauseTimestamps.append(Date())
        store.updateTrip(trip)
        trackingTask?.cancel()
        trackingTask = nil
        isTracking = false
        locationService?.stopBackgroundUpdating()
    }

    func resumeTracking() {
        guard let store, var trip = store.activeTrip, trip.isPaused else { return }
        trip.isPaused = false
        trip.resumeTimestamps.append(Date())
        store.updateTrip(trip)
        startTracking()
    }

    func stopTracking() {
        trackingTask?.cancel()
        trackingTask = nil
        isTracking = false
        locationService?.stopBackgroundUpdating()
    }

    func resumeIfNeeded() {
        guard let store else { return }
        if store.activeTrip != nil && !isTracking {
            startTracking()
        }
    }
}
