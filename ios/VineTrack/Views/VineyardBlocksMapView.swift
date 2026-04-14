import SwiftUI
import MapKit

struct VineyardBlocksMapView: View {
    @Environment(DataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @Binding var selectedPaddock: Paddock?
    var onAddBlock: (() -> Void)? = nil
    @State private var position: MapCameraPosition = .automatic
    @State private var hasSetInitialPosition: Bool = false

    private var paddocks: [Paddock] {
        store.orderedPaddocks
    }

    private var blockColors: [UUID: Color] {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .red, .cyan, .mint, .indigo, .pink, .teal, .yellow, .brown
        ]
        var map: [UUID: Color] = [:]
        for (i, paddock) in paddocks.enumerated() {
            map[paddock.id] = palette[i % palette.count]
        }
        return map
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                ForEach(paddocks) { paddock in
                    if paddock.polygonPoints.count > 2 {
                        let color = blockColors[paddock.id] ?? .blue
                        MapPolygon(coordinates: paddock.polygonPoints.map { $0.coordinate })
                            .foregroundStyle(color.opacity(0.25))
                            .stroke(color, lineWidth: 2.5)

                        Annotation("", coordinate: paddock.polygonPoints.centroid) {
                            Button {
                                selectedPaddock = paddock
                            } label: {
                                Text(paddock.name)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        (blockColors[paddock.id] ?? .blue).opacity(0.85),
                                        in: .capsule
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                            }
                        }
                    }
                }

                UserAnnotation()
            }
            .mapStyle(.hybrid)
            .clipShape(.rect(cornerRadius: 12))

            VStack(spacing: 8) {
                if let onAddBlock {
                    Button {
                        onAddBlock()
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.blue, in: .circle)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    }
                }

                if paddocks.contains(where: { $0.polygonPoints.count > 2 }) {
                    Button {
                        withAnimation(.smooth(duration: 0.4)) {
                            fitAllBlocks()
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                }
            }
            .padding(8)
        }
        .frame(height: 280)
        .onAppear {
            locationService.requestPermission()
            locationService.startUpdating()
            fitInitialPosition()
        }
        .onChange(of: locationService.location) { _, newLocation in
            if !hasSetInitialPosition, let loc = newLocation {
                if paddocks.allSatisfy({ $0.polygonPoints.count < 3 }) {
                    position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 1000))
                    hasSetInitialPosition = true
                }
            }
        }
    }

    private func fitInitialPosition() {
        let blocksWithBounds = paddocks.filter { $0.polygonPoints.count > 2 }
        guard !blocksWithBounds.isEmpty else {
            if let loc = locationService.location {
                position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 1000))
                hasSetInitialPosition = true
            }
            return
        }
        fitAllBlocks()
        hasSetInitialPosition = true
    }

    private func fitAllBlocks() {
        let allPoints = paddocks.flatMap { $0.polygonPoints }
        guard !allPoints.isEmpty else { return }

        let minLat = allPoints.map(\.latitude).min()!
        let maxLat = allPoints.map(\.latitude).max()!
        let minLon = allPoints.map(\.longitude).min()!
        let maxLon = allPoints.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 0.001,
            longitudeDelta: (maxLon - minLon) * 1.4 + 0.001
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}
