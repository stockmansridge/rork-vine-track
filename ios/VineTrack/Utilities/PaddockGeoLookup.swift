import CoreLocation

struct PaddockGeoLookupResult {
    let paddockId: UUID
    let closestRowNumber: Int?
}

func findPaddockAndRow(
    coordinate: CLLocationCoordinate2D,
    paddocks: [Paddock]
) -> PaddockGeoLookupResult? {
    for paddock in paddocks {
        guard paddock.polygonPoints.count >= 3 else { continue }
        let polygon = paddock.polygonPoints.map { $0.coordinate }
        guard pointInPolygon(point: coordinate, polygon: polygon) else { continue }

        let closestRow = findClosestRow(coordinate: coordinate, paddock: paddock)
        return PaddockGeoLookupResult(paddockId: paddock.id, closestRowNumber: closestRow)
    }
    return nil
}

private func findClosestRow(
    coordinate: CLLocationCoordinate2D,
    paddock: Paddock
) -> Int? {
    guard !paddock.rows.isEmpty else {
        return findClosestRowFromGeometry(coordinate: coordinate, paddock: paddock)
    }

    let hasValidCoords = paddock.rows.contains { row in
        row.startPoint.latitude != 0 || row.startPoint.longitude != 0 ||
        row.endPoint.latitude != 0 || row.endPoint.longitude != 0
    }

    guard hasValidCoords else {
        return findClosestRowFromGeometry(coordinate: coordinate, paddock: paddock)
    }

    var bestRow: Int?
    var bestDist: Double = .greatestFiniteMagnitude

    for row in paddock.rows {
        let dist = distanceFromPointToSegment(
            point: coordinate,
            segStart: row.startPoint.coordinate,
            segEnd: row.endPoint.coordinate
        )
        if dist < bestDist {
            bestDist = dist
            bestRow = row.number
        }
    }
    return bestRow
}

private func findClosestRowFromGeometry(
    coordinate: CLLocationCoordinate2D,
    paddock: Paddock
) -> Int? {
    let polygon = paddock.polygonPoints.map { $0.coordinate }
    guard polygon.count >= 3 else { return nil }

    let rowCount = max(1, Int(round(estimateRowCount(polygon: polygon, rowWidth: paddock.rowWidth))))
    let lines = calculateRowLines(
        polygonCoords: polygon,
        direction: paddock.rowDirection,
        count: rowCount,
        width: paddock.rowWidth,
        offset: paddock.rowOffset
    )
    guard !lines.isEmpty else { return nil }

    var bestIndex: Int?
    var bestDist: Double = .greatestFiniteMagnitude

    for (i, line) in lines.enumerated() {
        let dist = distanceFromPointToSegment(
            point: coordinate,
            segStart: line.start,
            segEnd: line.end
        )
        if dist < bestDist {
            bestDist = dist
            bestIndex = i
        }
    }

    guard let idx = bestIndex else { return nil }

    if !paddock.rows.isEmpty && idx < paddock.rows.count {
        return paddock.rows[idx].number
    }
    return idx + 1
}

private func estimateRowCount(polygon: [CLLocationCoordinate2D], rowWidth: Double) -> Double {
    let mPerDegLat: Double = 111_320.0
    let centroidLat = polygon.map(\.latitude).reduce(0, +) / Double(polygon.count)
    let mPerDegLon = 111_320.0 * cos(centroidLat * .pi / 180.0)

    var maxDist: Double = 0
    for i in 0..<polygon.count {
        for j in (i + 1)..<polygon.count {
            let dLat = (polygon[i].latitude - polygon[j].latitude) * mPerDegLat
            let dLon = (polygon[i].longitude - polygon[j].longitude) * mPerDegLon
            maxDist = max(maxDist, sqrt(dLat * dLat + dLon * dLon))
        }
    }
    guard rowWidth > 0 else { return 1 }
    return maxDist / rowWidth
}

private func distanceFromPointToSegment(
    point: CLLocationCoordinate2D,
    segStart: CLLocationCoordinate2D,
    segEnd: CLLocationCoordinate2D
) -> Double {
    let mPerDegLat: Double = 111_320.0
    let avgLat = (point.latitude + segStart.latitude + segEnd.latitude) / 3.0
    let mPerDegLon = 111_320.0 * cos(avgLat * .pi / 180.0)

    let px = (point.longitude - segStart.longitude) * mPerDegLon
    let py = (point.latitude - segStart.latitude) * mPerDegLat
    let dx = (segEnd.longitude - segStart.longitude) * mPerDegLon
    let dy = (segEnd.latitude - segStart.latitude) * mPerDegLat

    let lenSq = dx * dx + dy * dy
    guard lenSq > 1e-14 else {
        return sqrt(px * px + py * py)
    }

    let t = max(0, min(1, (px * dx + py * dy) / lenSq))
    let projX = t * dx
    let projY = t * dy
    let distX = px - projX
    let distY = py - projY
    return sqrt(distX * distX + distY * distY)
}

private func pointInPolygon(
    point: CLLocationCoordinate2D,
    polygon: [CLLocationCoordinate2D]
) -> Bool {
    let n = polygon.count
    guard n >= 3 else { return false }
    var inside = false
    var j = n - 1
    for i in 0..<n {
        let yi = polygon[i].latitude
        let xi = polygon[i].longitude
        let yj = polygon[j].latitude
        let xj = polygon[j].longitude

        if ((yi > point.latitude) != (yj > point.latitude)) &&
            (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi) {
            inside.toggle()
        }
        j = i
    }
    return inside
}
