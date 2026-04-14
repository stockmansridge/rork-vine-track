import SwiftUI
import MapKit

struct FullScreenPathMapView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss) private var dismiss
    let paddocks: [Paddock]
    let sampleSites: [SampleSite]
    let pathWaypoints: [CoordinatePoint]
    let blockColors: [Color]
    let colorForPaddock: (Paddock) -> Color
    let onSiteSelected: (SampleSite) -> Void

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $mapPosition) {
                UserAnnotation()

                ForEach(paddocks) { paddock in
                    let color = colorForPaddock(paddock)

                    MapPolygon(coordinates: paddock.polygonPoints.map(\.coordinate))
                        .foregroundStyle(color.opacity(0.15))
                        .stroke(color.opacity(0.5), lineWidth: 1.5)

                    ForEach(paddock.rows) { row in
                        MapPolyline(coordinates: [row.startPoint.coordinate, row.endPoint.coordinate])
                            .stroke(color.opacity(0.15), lineWidth: 0.5)
                    }
                }

                MapPolyline(coordinates: pathWaypoints.map(\.coordinate))
                    .stroke(
                        .linearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 3
                    )

                ForEach(sampleSites) { site in
                    let paddock = paddocks.first { $0.id == site.paddockId }
                    let color = paddock.map { colorForPaddock($0) } ?? .red
                    let isRecorded = site.isRecorded

                    Annotation("", coordinate: site.coordinate) {
                        Button {
                            onSiteSelected(site)
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    Circle()
                                        .fill(isRecorded ? .green : color)
                                        .frame(width: 30, height: 30)
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 20, height: 20)
                                    if isRecorded {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("\(site.siteIndex)")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundStyle(color)
                                    }
                                }
                                if let userLoc = locationService.location {
                                    let dist = userLoc.distance(from: CLLocation(latitude: site.latitude, longitude: site.longitude))
                                    Text(formatDistance(dist))
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(isRecorded ? .green : color, in: .capsule)
                                }
                            }
                        }
                    }
                }

                if pathWaypoints.count >= 2 {
                    Annotation("Start", coordinate: pathWaypoints[0].coordinate) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(4)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 2)
                    }
                    Annotation("End", coordinate: pathWaypoints[pathWaypoints.count - 1].coordinate) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(4)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 2)
                    }
                }

                ForEach(arrowAnnotations, id: \.id) { arrow in
                    Annotation("", coordinate: arrow.coordinate) {
                        Image(systemName: "arrowtriangle.forward.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .rotationEffect(.degrees(arrow.bearing))
                            .allowsHitTesting(false)
                    }
                }
            }
            .mapStyle(.hybrid)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4)
                }

                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        if isTrackingUser, let loc = locationService.location {
                            mapPosition = .camera(MapCamera(
                                centerCoordinate: loc.coordinate,
                                distance: 500
                            ))
                        } else {
                            fitMapToContent()
                        }
                        isTrackingUser.toggle()
                    }
                } label: {
                    Image(systemName: isTrackingUser ? "location.fill" : "location")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isTrackingUser ? .blue : .primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4)
                }

                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        fitMapToContent()
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4)
                }
            }
            .padding(.top, 60)
            .padding(.leading, 16)

            VStack {
                Spacer()
                HStack(spacing: 16) {
                    legendItem(icon: "flag.fill", color: .green, label: "Start")
                    legendItem(icon: "flag.checkered", color: .red, label: "End")
                    legendItem(icon: "circle.fill", color: .orange, label: "Unrecorded")
                    legendItem(icon: "checkmark.circle.fill", color: .green, label: "Recorded")
                    legendItem(icon: "location.fill", color: .blue, label: "You")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.15), radius: 4)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            locationService.requestPermission()
            locationService.startUpdating()
            fitMapToContent()
        }
        .onDisappear {
            locationService.stopUpdating()
        }
    }

    private func legendItem(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0fm", meters)
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }

    private func fitMapToContent() {
        let allPoints = paddocks.flatMap(\.polygonPoints)
        let allLats = allPoints.map(\.latitude) + sampleSites.map(\.latitude)
        let allLons = allPoints.map(\.longitude) + sampleSites.map(\.longitude)

        guard let minLat = allLats.min(), let maxLat = allLats.max(),
              let minLon = allLons.min(), let maxLon = allLons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 0.001,
            longitudeDelta: (maxLon - minLon) * 1.4 + 0.001
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        isTrackingUser = false
    }

    private struct ArrowAnnotation: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
        let bearing: Double
    }

    private var arrowAnnotations: [ArrowAnnotation] {
        guard pathWaypoints.count >= 2 else { return [] }
        var arrows: [ArrowAnnotation] = []
        let step = max(1, pathWaypoints.count / 15)
        for i in stride(from: step, to: pathWaypoints.count, by: step) {
            let prev = pathWaypoints[i - 1]
            let curr = pathWaypoints[i]
            let dLat = curr.latitude - prev.latitude
            let dLon = curr.longitude - prev.longitude
            guard abs(dLat) > 1e-10 || abs(dLon) > 1e-10 else { continue }
            let bearing = atan2(dLon, dLat) * 180 / .pi
            let midLat = (prev.latitude + curr.latitude) / 2
            let midLon = (prev.longitude + curr.longitude) / 2
            arrows.append(ArrowAnnotation(
                id: i,
                coordinate: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                bearing: bearing
            ))
        }
        return arrows
    }
}
