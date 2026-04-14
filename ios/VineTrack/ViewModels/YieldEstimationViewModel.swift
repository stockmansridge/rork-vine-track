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
    var blockBunchWeightsKg: [UUID: Double] = [:]
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

    func calculateYieldEstimates(paddocks: [Paddock], damageFactorProvider: ((UUID) -> Double)? = nil) -> [BlockYieldEstimate] {
        let selected = paddocks.filter { selectedPaddockIds.contains($0.id) }
        var estimates: [BlockYieldEstimate] = []

        for paddock in selected {
            let sitesInPaddock = sampleSites.filter { $0.paddockId == paddock.id }
            let recordedSites = sitesInPaddock.filter { $0.isRecorded }
            let damageFactor = damageFactorProvider?(paddock.id) ?? 1.0

            guard !recordedSites.isEmpty else {
                estimates.append(BlockYieldEstimate(
                    paddockId: paddock.id,
                    paddockName: paddock.name,
                    areaHectares: paddock.areaHectares,
                    totalVines: paddock.effectiveVineCount,
                    averageBunchesPerVine: 0,
                    totalBunches: 0,
                    averageBunchWeightKg: bunchWeightKg(for: paddock.id),
                    damageFactor: damageFactor,
                    estimatedYieldKg: 0,
                    estimatedYieldTonnes: 0,
                    samplesRecorded: 0,
                    samplesTotal: sitesInPaddock.count,
                    damageRecords: []
                ))
                continue
            }

            let avgBunches = recordedSites.reduce(0.0) { $0 + ($1.bunchCountEntry?.bunchesPerVine ?? 0) } / Double(recordedSites.count)
            let avgBunchesRounded = (avgBunches * 100).rounded() / 100

            let totalVines = paddock.effectiveVineCount
            let totalBunches = Double(totalVines) * avgBunchesRounded
            let blockWeight = bunchWeightKg(for: paddock.id)
            let yieldKg = totalBunches * blockWeight * damageFactor
            let yieldTonnes = yieldKg / 1000.0

            estimates.append(BlockYieldEstimate(
                paddockId: paddock.id,
                paddockName: paddock.name,
                areaHectares: paddock.areaHectares,
                totalVines: totalVines,
                averageBunchesPerVine: avgBunchesRounded,
                totalBunches: totalBunches,
                averageBunchWeightKg: blockWeight,
                damageFactor: damageFactor,
                estimatedYieldKg: yieldKg,
                estimatedYieldTonnes: yieldTonnes,
                samplesRecorded: recordedSites.count,
                samplesTotal: sitesInPaddock.count,
                damageRecords: []
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
        blockBunchWeightsKg = session.blockBunchWeightsKg
        previousBunchWeights = session.previousBunchWeights
    }

    func toSession(vineyardId: UUID, samplesPerHectare: Int) -> YieldEstimationSession {
        YieldEstimationSession(
            id: sessionId ?? UUID(),
            vineyardId: vineyardId,
            selectedPaddockIds: Array(selectedPaddockIds),
            samplesPerHectare: samplesPerHectare,
            sampleSites: sampleSites,
            blockBunchWeightsKg: blockBunchWeightsKg,
            previousBunchWeights: previousBunchWeights,
            pathWaypoints: pathWaypoints
        )
    }

    // MARK: - Sample Generation

    func bunchWeightKg(for paddockId: UUID) -> Double {
        blockBunchWeightsKg[paddockId] ?? 0.15
    }

    func setBunchWeight(_ weightKg: Double, for paddockId: UUID) {
        blockBunchWeightsKg[paddockId] = weightKg
    }

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
        let polygon = paddock.polygonPoints
        guard !rows.isEmpty, polygon.count >= 3 else { return [] }

        let mPerDegLat = 111_320.0
        let centroidLat = polygon.map(\.latitude).reduce(0, +) / Double(polygon.count)
        let mPerDegLon = 111_320.0 * cos(centroidLat * .pi / 180.0)

        struct ClippedSegment {
            let row: PaddockRow
            let startLat: Double
            let startLon: Double
            let endLat: Double
            let endLon: Double
            let length: Double
        }

        var clippedSegments: [ClippedSegment] = []

        for row in rows {
            let segments = clipRowToPolygon(row: row, polygon: polygon)
            for seg in segments {
                let dLat = (seg.endLat - seg.startLat) * mPerDegLat
                let dLon = (seg.endLon - seg.startLon) * mPerDegLon
                let length = sqrt(dLat * dLat + dLon * dLon)
                guard length > 0.5 else { continue }
                clippedSegments.append(ClippedSegment(
                    row: row,
                    startLat: seg.startLat, startLon: seg.startLon,
                    endLat: seg.endLat, endLon: seg.endLon,
                    length: length
                ))
            }
        }

        guard !clippedSegments.isEmpty else { return [] }

        let totalLength = clippedSegments.reduce(0.0) { $0 + $1.length }
        guard totalLength > 0 else { return [] }

        let spacingMetres = totalLength / Double(totalSamples + 1)

        var sites: [SampleSite] = []
        var accumulatedDistance: Double = 0
        var nextSiteDistance = spacingMetres
        var siteIndex = startIndex

        for seg in clippedSegments {
            let segStartDist = accumulatedDistance
            let segEndDist = accumulatedDistance + seg.length

            while nextSiteDistance <= segEndDist && sites.count < totalSamples {
                let distAlong = nextSiteDistance - segStartDist
                let fraction = distAlong / seg.length

                let lat = seg.startLat + fraction * (seg.endLat - seg.startLat)
                let lon = seg.startLon + fraction * (seg.endLon - seg.startLon)

                let site = SampleSite(
                    paddockId: paddock.id,
                    paddockName: paddock.name,
                    rowNumber: seg.row.number,
                    latitude: lat,
                    longitude: lon,
                    siteIndex: siteIndex
                )
                sites.append(site)
                siteIndex += 1
                nextSiteDistance += spacingMetres
            }

            accumulatedDistance = segEndDist
        }

        if sites.count < totalSamples {
            let remaining = totalSamples - sites.count
            let segCount = clippedSegments.count
            for i in 0..<remaining {
                let seg = clippedSegments[i % segCount]
                let fraction = Double(i + 1) / Double(remaining + 1)
                let lat = seg.startLat + fraction * (seg.endLat - seg.startLat)
                let lon = seg.startLon + fraction * (seg.endLon - seg.startLon)

                let site = SampleSite(
                    paddockId: paddock.id,
                    paddockName: paddock.name,
                    rowNumber: seg.row.number,
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

    private struct RowSegment {
        let startLat: Double
        let startLon: Double
        let endLat: Double
        let endLon: Double
    }

    private func clipRowToPolygon(row: PaddockRow, polygon: [CoordinatePoint]) -> [RowSegment] {
        let ax = row.startPoint.longitude
        let ay = row.startPoint.latitude
        let bx = row.endPoint.longitude
        let by = row.endPoint.latitude
        let dx = bx - ax
        let dy = by - ay

        var tValues: [Double] = [0.0, 1.0]

        let n = polygon.count
        for i in 0..<n {
            let j = (i + 1) % n
            let cx = polygon[i].longitude
            let cy = polygon[i].latitude
            let ex = polygon[j].longitude - cx
            let ey = polygon[j].latitude - cy

            let denom = dx * ey - dy * ex
            guard abs(denom) > 1e-15 else { continue }

            let t = ((cx - ax) * ey - (cy - ay) * ex) / denom
            let u = ((cx - ax) * dy - (cy - ay) * dx) / denom

            if u >= 0 && u <= 1 && t > -0.001 && t < 1.001 {
                tValues.append(min(max(t, 0), 1))
            }
        }

        tValues.sort()

        var segments: [RowSegment] = []
        for i in 0..<(tValues.count - 1) {
            let t0 = tValues[i]
            let t1 = tValues[i + 1]
            guard t1 - t0 > 1e-10 else { continue }

            let midT = (t0 + t1) / 2.0
            let midLat = ay + midT * dy
            let midLon = ax + midT * dx

            if pointInPolygon(lat: midLat, lon: midLon, polygon: polygon) {
                segments.append(RowSegment(
                    startLat: ay + t0 * dy, startLon: ax + t0 * dx,
                    endLat: ay + t1 * dy, endLon: ax + t1 * dx
                ))
            }
        }

        return segments
    }

    private func pointInPolygon(lat: Double, lon: Double, polygon: [CoordinatePoint]) -> Bool {
        let n = polygon.count
        guard n >= 3 else { return false }
        var inside = false
        var j = n - 1
        for i in 0..<n {
            let yi = polygon[i].latitude
            let xi = polygon[i].longitude
            let yj = polygon[j].latitude
            let xj = polygon[j].longitude

            if ((yi > lat) != (yj > lat)) &&
                (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
