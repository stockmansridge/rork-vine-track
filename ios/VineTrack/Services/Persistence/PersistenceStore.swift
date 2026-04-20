import Foundation

/// Shared file-based persistence used by domain repositories.
/// Owns low-level JSON encode/decode + atomic write under `VineTrackData/`.
@MainActor
final class PersistenceStore {

    static let shared = PersistenceStore()

    let directory: URL

    init(directory: URL = PersistenceStore.defaultDirectory) {
        self.directory = directory
    }

    static let defaultDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("VineTrackData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func save<T: Encodable>(_ data: T, key: String) {
        do {
            let encoded = try JSONEncoder().encode(data)
            let fileURL = directory.appendingPathComponent("\(key).json")
            try encoded.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("PersistenceStore: Failed to save \(key): \(error)")
        }
    }

    func load<T: Decodable>(key: String) -> T? {
        let fileURL = directory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("PersistenceStore: Failed to decode \(key): \(error)")
            return nil
        }
    }

    func removeFile(key: String) {
        let fileURL = directory.appendingPathComponent("\(key).json")
        try? FileManager.default.removeItem(at: fileURL)
    }
}
