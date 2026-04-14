import Foundation
import UniformTypeIdentifiers

nonisolated struct BlockExportData: Codable, Sendable {
    let version: Int
    let exportDate: Date
    let vineyardName: String
    let paddocks: [Paddock]

    init(vineyardName: String, paddocks: [Paddock]) {
        self.version = 1
        self.exportDate = Date()
        self.vineyardName = vineyardName
        self.paddocks = paddocks
    }
}

struct BlockExportImportService {
    static func exportBlocks(paddocks: [Paddock], vineyardName: String) throws -> Data {
        let exportData = BlockExportData(vineyardName: vineyardName, paddocks: paddocks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportData)
    }

    static func parseImportData(_ data: Data) throws -> BlockExportData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BlockExportData.self, from: data)
    }

    static func importBlocks(from importData: BlockExportData, into store: DataStore, replaceExisting: Bool) -> Int {
        guard let vid = store.selectedVineyardId else { return 0 }
        var imported = 0

        if replaceExisting {
            for existing in store.paddocks {
                store.deletePaddock(existing)
            }
        }

        for var paddock in importData.paddocks {
            if replaceExisting || !store.paddocks.contains(where: { $0.name == paddock.name }) {
                paddock.vineyardId = vid
                store.addPaddock(Paddock(
                    id: UUID(),
                    vineyardId: vid,
                    name: paddock.name,
                    polygonPoints: paddock.polygonPoints.map { CoordinatePoint(latitude: $0.latitude, longitude: $0.longitude) },
                    rows: paddock.rows.map { PaddockRow(number: $0.number, startPoint: CoordinatePoint(latitude: $0.startPoint.latitude, longitude: $0.startPoint.longitude), endPoint: CoordinatePoint(latitude: $0.endPoint.latitude, longitude: $0.endPoint.longitude)) },
                    rowDirection: paddock.rowDirection,
                    rowWidth: paddock.rowWidth,
                    rowOffset: paddock.rowOffset,
                    vineSpacing: paddock.vineSpacing,
                    vineCountOverride: paddock.vineCountOverride
                ))
                imported += 1
            }
        }
        return imported
    }

    static func exportFileURL(vineyardName: String, data: Data) throws -> URL {
        let sanitized = vineyardName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(sanitized)_blocks.json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)
        return tempURL
    }
}
