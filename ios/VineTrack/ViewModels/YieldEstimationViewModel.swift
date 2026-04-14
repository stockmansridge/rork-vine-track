import Foundation
import CoreLocation

@Observable
@MainActor
class YieldEstimationViewModel {
    var selectedPaddockIds: Set<UUID> = []
    var sampleSites: [SampleSite] = []
    var isGenerated: Bool = false

    func togglePaddock(_ paddockId: UUID) {
        if selectedPaddockIds.contains(paddockId) {
            selectedPaddockIds.remove(paddockId)
        } else {
            selectedPaddockIds.insert(paddockId)
        }
        sampleSites = []
        isGenerated = false
    }

    func selectAll(paddocks: [Paddock]) {
        selectedPaddockIds = Set(paddocks.map(\.id))
        sampleSites = []
        isGenerated = false
    }

    func deselectAll() {
        selectedPaddockIds.removeAll()
        sampleSites = []
        isGenerated = false
    }

    func generateSampleSites(paddocks: [Paddock], samplesPerHectare: Int) {
        var allSites: [SampleSite] = []
        var globalIndex = 1

        let selected = paddocks.filter { selectedPaddockIds.contains($0.id) }

        for paddock in selected {
            let area = paddock.areaHectares
            guard area > 0 else { continue }

            let totalSamples = max(1, Int(round(Double(samplesPerHectare) * area)))

            let sites = generateSitesOnRows(
                paddock: paddock,
                totalSamples: totalSamples,
                startIndex: globalIndex
            )

            allSites.append(contentsOf: sites)
            globalIndex += sites.count
        }

        sampleSites = allSites
        isGenerated = true
    }

    private func generateSitesOnRows(paddock: Paddock, totalSamples: Int, startIndex: Int) -> [SampleSite] {
        let rows = paddock.rows
        guard !rows.isEmpty else { return [] }

        let mPerDegLat = 111_320.0
        let centroidLat = paddock.polygonPoints.isEmpty ? 0 : paddock.polygonPoints.map(\.latitude).reduce(0, +) / Double(paddock.polygonPoints.count)
        let mPerDegLon = 111_320.0 * cos(centroidLat * .pi / 180.0)

        struct RowWithLength {
            let row: PaddockRow
            let length: Double
        }

        let rowsWithLength: [RowWithLength] = rows.compactMap { row in
            let dLat = (row.endPoint.latitude - row.startPoint.latitude) * mPerDegLat
            let dLon = (row.endPoint.longitude - row.startPoint.longitude) * mPerDegLon
            let length = sqrt(dLat * dLat + dLon * dLon)
            guard length > 0 else { return nil }
            return RowWithLength(row: row, length: length)
        }

        guard !rowsWithLength.isEmpty else { return [] }

        let totalRowLength = rowsWithLength.reduce(0.0) { $0 + $1.length }
        guard totalRowLength > 0 else { return [] }

        let spacingMetres = totalRowLength / Double(totalSamples + 1)

        var sites: [SampleSite] = []
        var accumulatedDistance: Double = 0
        var nextSiteDistance = spacingMetres
        var siteIndex = startIndex

        for rowData in rowsWithLength {
            let row = rowData.row
            let rowLength = rowData.length
            let rowStartDist = accumulatedDistance
            let rowEndDist = accumulatedDistance + rowLength

            while nextSiteDistance <= rowEndDist && sites.count < totalSamples {
                let distAlongRow = nextSiteDistance - rowStartDist
                let fraction = distAlongRow / rowLength

                let lat = row.startPoint.latitude + fraction * (row.endPoint.latitude - row.startPoint.latitude)
                let lon = row.startPoint.longitude + fraction * (row.endPoint.longitude - row.startPoint.longitude)

                let site = SampleSite(
                    paddockId: paddock.id,
                    paddockName: paddock.name,
                    rowNumber: row.number,
                    latitude: lat,
                    longitude: lon,
                    siteIndex: siteIndex
                )
                sites.append(site)
                siteIndex += 1
                nextSiteDistance += spacingMetres
            }

            accumulatedDistance = rowEndDist
        }

        if sites.count < totalSamples {
            let remaining = totalSamples - sites.count
            let rowCount = rowsWithLength.count
            for i in 0..<remaining {
                let rowData = rowsWithLength[i % rowCount]
                let row = rowData.row
                let fraction = Double.random(in: 0.15...0.85)
                let lat = row.startPoint.latitude + fraction * (row.endPoint.latitude - row.startPoint.latitude)
                let lon = row.startPoint.longitude + fraction * (row.endPoint.longitude - row.startPoint.longitude)

                let site = SampleSite(
                    paddockId: paddock.id,
                    paddockName: paddock.name,
                    rowNumber: row.number,
                    latitude: lat,
                    longitude: lon,
                    siteIndex: siteIndex
                )
                sites.append(site)
                siteIndex += 1
            }
        }

        return sites
    }

    var totalSelectedArea: Double {
        0
    }

    func totalSelectedArea(paddocks: [Paddock]) -> Double {
        paddocks
            .filter { selectedPaddockIds.contains($0.id) }
            .reduce(0) { $0 + $1.areaHectares }
    }

    func expectedSampleCount(paddocks: [Paddock], samplesPerHectare: Int) -> Int {
        paddocks
            .filter { selectedPaddockIds.contains($0.id) }
            .reduce(0) { total, paddock in
                total + max(1, Int(round(Double(samplesPerHectare) * paddock.areaHectares)))
            }
    }
}
