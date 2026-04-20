import Foundation
import UIKit

extension DataStore {

    // MARK: - Custom EL Stage Images

    static let elStageImagesDir: URL = {
        let dir = storageDirectory.appendingPathComponent("ELStageImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func elStageImageURL(for vineyardId: UUID, code: String) -> URL {
        let vineyardDir = Self.elStageImagesDir.appendingPathComponent(vineyardId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: vineyardDir, withIntermediateDirectories: true)
        return vineyardDir.appendingPathComponent("\(code).jpg")
    }

    func customELStageImage(for code: String) -> UIImage? {
        guard let vid = selectedVineyardId else { return nil }
        let url = elStageImageURL(for: vid, code: code)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func saveCustomELStageImage(_ image: UIImage, for code: String) {
        guard let vid = selectedVineyardId else { return }
        let url = elStageImageURL(for: vid, code: code)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: url, options: .atomic)
        updateELStageImageManifest(vineyardId: vid, code: code, removed: false)
        if let sync = cloudSync {
            Task {
                try? await sync.uploadELStageImage(data, vineyardId: vid, code: code)
                syncDataToCloud(dataType: "el_stage_images_manifest")
            }
        }
    }

    func removeCustomELStageImage(for code: String) {
        guard let vid = selectedVineyardId else { return }
        let url = elStageImageURL(for: vid, code: code)
        try? FileManager.default.removeItem(at: url)
        updateELStageImageManifest(vineyardId: vid, code: code, removed: true)
        if let sync = cloudSync {
            Task {
                await sync.removeELStageImage(vineyardId: vid, code: code)
                syncDataToCloud(dataType: "el_stage_images_manifest")
            }
        }
    }

    // MARK: - EL Stage Image Manifest

    static let elStageImagesManifestKey = "vinetrack_el_stage_images_manifest"

    func loadManifestDict() -> [String: [String: String]] {
        (UserDefaults.standard.dictionary(forKey: Self.elStageImagesManifestKey) as? [String: [String: String]]) ?? [:]
    }

    func saveManifestDict(_ dict: [String: [String: String]]) {
        UserDefaults.standard.set(dict, forKey: Self.elStageImagesManifestKey)
    }

    func elStageImageManifest(for vineyardId: UUID) -> ELStageImageManifest {
        let dict = loadManifestDict()
        let entries = (dict[vineyardId.uuidString] ?? [:]).map {
            ELStageImageManifestEntry(code: $0.key, updated_at: $0.value)
        }.sorted { $0.code < $1.code }
        return ELStageImageManifest(entries: entries)
    }

    func updateELStageImageManifest(vineyardId: UUID, code: String, removed: Bool) {
        var dict = loadManifestDict()
        var vineyardEntries = dict[vineyardId.uuidString] ?? [:]
        if removed {
            vineyardEntries.removeValue(forKey: code)
        } else {
            vineyardEntries[code] = ISO8601DateFormatter().string(from: Date())
        }
        dict[vineyardId.uuidString] = vineyardEntries
        saveManifestDict(dict)
    }

    func applyELStageImageManifest(_ manifest: ELStageImageManifest, for vineyardId: UUID, using sync: CloudSyncService) {
        var dict = loadManifestDict()
        let previous = dict[vineyardId.uuidString] ?? [:]
        var next: [String: String] = [:]
        for entry in manifest.entries {
            next[entry.code] = entry.updated_at
        }
        dict[vineyardId.uuidString] = next
        saveManifestDict(dict)

        for (code, _) in previous where next[code] == nil {
            let url = elStageImageURL(for: vineyardId, code: code)
            try? FileManager.default.removeItem(at: url)
        }

        for entry in manifest.entries {
            let url = elStageImageURL(for: vineyardId, code: entry.code)
            let exists = FileManager.default.fileExists(atPath: url.path)
            let prevStamp = previous[entry.code]
            if exists && prevStamp == entry.updated_at { continue }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let data = try await sync.downloadELStageImage(vineyardId: vineyardId, code: entry.code)
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("DataStore: Failed to download EL stage image \(entry.code): \(error)")
                }
            }
        }
    }

    func hasCustomELStageImage(for code: String) -> Bool {
        guard let vid = selectedVineyardId else { return false }
        let url = elStageImageURL(for: vid, code: code)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func resolvedELStageImage(for stage: GrowthStage) -> UIImage? {
        if let custom = customELStageImage(for: stage.code) {
            return custom
        }
        if stage.imageName != nil {
            return UIImage(named: stage.code)
        }
        return nil
    }
}
