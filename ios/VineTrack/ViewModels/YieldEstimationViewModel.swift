import Foundation
import CoreLocation

@Observable
@MainActor
class YieldEstimationViewModel {
    var selectedPaddockIds: Set<UUID> = []
    var sampleSites: [SampleSite] = []
    var isGenerated: Bool = false
    var pathWaypoints: [CoordinatePoint] = []
    var isPathGenerated: Bool = false
    var averageBunchWeightKg: Double = 0.15
    var previousBunchWeights: [BunchWeightRecord] = []
    var selectedSite: SampleSite?
    var sessionId: UUID?

    func togglePaddock(_ paddockId: UUID) {
        if selectedPaddockIds.contains(paddockId) {
            selectedPaddockIds.remove(paddockId)
        } else {
            selectedPaddockIds.insert(paddockId)
        }
        sampleSites = []
        isGenerated = false
        pathWaypoints = []
        isPathGenerated = false
    }

    func selectAll(paddocks: [Paddock]) {
        selectedPaddockIds = Set(paddocks.map(\.id))
        sampleSites = []
        isGenerated = false
        pathWaypoints = []
        isPathGenerated = false
    }

    func deselectAll() {
        selectedPaddockIds.removeAll()
        sampleSites = []
        isGenerated = false
        pathWaypoints = []
        isPathGenerated = false
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
        pathWaypoints = []
        isPathGenerated = false
        sessionId = UUID()
    }

    func recordBunchCount(siteId: UUID, bunchesPerVine: Double, recordedBy: String) {
        guard let index = sampleSites.firstIndex(where: { $0.id == siteId }) else { return }
        sampleSites[index].bunchCountEntry = BunchCountEntry(
            bunchesPerVine: bunchesPerVine,
            recordedAt: Date(),
            recordedBy: recordedBy
        )
    }

    func generatePath(paddocks: [Paddock]) {
        guard !sampleSites.isEmpty else { return }

        let selected = paddocks.filter { selectedPaddockIds.contains($0.id) }
        var waypoints: [CoordinatePoint] = []

        for paddock in selected {
            let sitesInPaddock = sampleSites.filter { $0.paddockId == paddock.id }
            guard !sitesInPaddock.isEmpty else { continue }

            let sorted = sortSitesForPath(sites: sitesInPaddock, paddock: paddock)

            for i in 0..<sorted.count {
                let site = sorted[i]

                if i > 0 {
                    let prev = sorted[i - 1]
                    let connectorPoints = generateRowConnector(
                        from: prev,
                        to: site,
                        paddock: paddock
                    )
                    waypoints.append(contentsOf: connectorPoints)
                }

                waypoints.append(CoordinatePoint(latitude: site.latitude, longitude: site.longitude))
            }
        }

        pathWaypoints = waypoints
        isPathGenerated = true
    }

    private func sortSitesForPath(sites: [SampleSite], paddock: Paddock) -> [SampleSite] {
        let rowGroups = Dictionary(grouping: sites, by: \.rowNumber)
        let sortedRowNumbers = rowGroups.keys.sorted()

        var result: [SampleSite] = []

        for rowNum in sortedRowNumbers {
            guard var rowSites = rowGroups[rowNum] else { continue }

            let row = paddock.rows.first { $0.number == rowNum }
            if let row {
                let bearing = atan2(
                    row.endPoint.longitude - row.startPoint.longitude,
                    row.endPoint.latitude - row.startPoint.latitude
                )
                rowSites.sort { a, b in
                    let projA = (a.latitude - row.startPoint.latitude) * cos(bearing) + (a.longitude - row.startPoint.longitude) * sin(bearing)
                    let projB = (b.latitude - row.startPoint.latitude) * cos(bearing) + (b.longitude - row.startPoint.longitude) * sin(bearing)
                    return projA < projB
                }
            }

            result.append(contentsOf: rowSites)
        }

        return result
    }

    private func generateRowConnector(from: SampleSite, to: SampleSite, paddock: Paddock) -> [CoordinatePoint] {
        guard from.rowNumber != to.rowNumber else { return [] }

        let fromRow = paddock.rows.first { $0.number == from.rowNumber }
        let toRow = paddock.rows.first { $0.number == to.rowNumber }
        guard let fromRow, let toRow else { return [] }

        let fromEnd = closerEnd(of: fromRow, to: CoordinatePoint(latitude: from.latitude, longitude: from.longitude))
        let toStart = closerEnd(of: toRow, to: fromEnd)

        var points: [CoordinatePoint] = []
        points.append(fromEnd)
        if distance(fromEnd, toStart) > 0.00001 {
            points.append(toStart)
        }
        return points
    }

    private func closerEnd(of row: PaddockRow, to point: CoordinatePoint) -> CoordinatePoint {
        let dStart = distance(point, row.startPoint)
        let dEnd = distance(point, row.endPoint)
        return dStart <= dEnd ? row.startPoint : row.endPoint
    }

    private func distance(_ a: CoordinatePoint, _ b: CoordinatePoint) -> Double {
        let dLat = a.latitude - b.latitude
        let dLon = a.longitude - b.longitude
        return sqrt(dLat * dLat + dLon * dLon)
    }

    // MARK: - Yield Calculation

    func calculateYieldEstimates(paddocks: [Paddock]) -> [BlockYieldEstimate] {
        let selected = paddocks.filter { selectedPaddockIds.contains($0.id) }
        var estimates: [BlockYieldEstimate] = []

        for paddock in selected {
            let sitesInPaddock = sampleSites.filter { $0.paddockId == paddock.id }
            let recordedSites = sitesInPaddock.filter { $0.isRecorded }

            guard !recordedSites.isEmpty else {
                estimates.append(BlockYieldEstimate(
                    paddockId: paddock.id,
                    paddockName: paddock.name,
                    areaHectares: paddock.areaHectares,
                    totalVines: paddock.effectiveVineCount,
                    averageBunchesPerVine: 0,
                    totalBunches: 0,
                    averageBunchWeightKg: averageBunchWeightKg,
                    damageFactor: 1.0,
                    estimatedYieldKg: 0,
                    estimatedYieldTonnes: 0,
                    samplesRecorded: 0,
                    samplesTotal: sitesInPaddock.count
                ))
                continue
            }

            let avgBunches = recordedSites.reduce(0.0) { $0 + ($1.bunchCountEntry?.bunchesPerVine ?? 0) } / Double(recordedSites.count)
            let avgBunchesRounded = (avgBunches * 100).rounded() / 100

            let totalVines = paddock.effectiveVineCount
            let totalBunches = Double(totalVines) * avgBunchesRounded
            let damageFactor = 1.0
            let yieldKg = totalBunches * averageBunchWeightKg * damageFactor
            let yieldTonnes = yieldKg / 1000.0

            estimates.append(BlockYieldEstimate(
                paddockId: paddock.id,
                paddockName: paddock.name,
                areaHectares: paddock.areaHectares,
                totalVines: totalVines,
                averageBunchesPerVine: avgBunchesRounded,
                totalBunches: totalBunches,
                averageBunchWeightKg: averageBunchWeightKg,
                damageFactor: damageFactor,
                estimatedYieldKg: yieldKg,
                estimatedYieldTonnes: yieldTonnes,
                samplesRecorded: recordedSites.count,
                samplesTotal: sitesInPaddock.count
            ))
        }

        return estimates
    }

    var recordedSiteCount: Int {
        sampleSites.filter { $0.isRecorded }.count
    }

    var totalSiteCount: Int {
        sampleSites.count
    }

    func loadSession(_ session: YieldEstimationSession) {
        sessionId = session.id
        selectedPaddockIds = Set(session.selectedPaddockIds)
        sampleSites = session.sampleSites
        isGenerated = !session.sampleSites.isEmpty
        pathWaypoints = session.pathWaypoints
        isPathGenerated = !session.pathWaypoints.isEmpty
        averageBunchWeightKg = session.averageBunchWeightKg
        previousBunchWeights = session.previousBunchWeights
    }

    func toSession(vineyardId: UUID, samplesPerHectare: Int) -> YieldEstimationSession {
        YieldEstimationSession(
            id: sessionId ?? UUID(),
            vineyardId: vineyardId,
            selectedPaddockIds: Array(selectedPaddockIds),
            samplesPerHectare: samplesPerHectare,
            sampleSites: sampleSites,
            averageBunchWeightKg: averageBunchWeightKg,
            previousBunchWeights: previousBunchWeights,
            pathWaypoints: pathWaypoints
        )
    }

    // MARK: - Sample Generation

    var totalSelectedArea: Double { 0 }

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
}
