import Foundation
import Observation
import OSLog

// boxes.json in Application Support - no passwords in here, just enough to look them up in Keychain
@MainActor
@Observable
final class BoxStore {
    private(set) var boxes: [StorageBox] = []

    private let fileURL: URL
    private let logger = Logger(subsystem: "de.silxnt.StorageBoxManager", category: "BoxStore")

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("StorageBoxManager", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.fileURL = support.appendingPathComponent("boxes.json")
        }
        load()
    }

    // MARK: - Mutations

    func add(_ box: StorageBox) {
        boxes.append(box)
        save()
    }

    func update(_ box: StorageBox) {
        guard let index = boxes.firstIndex(where: { $0.id == box.id }) else { return }
        boxes[index] = box
        save()
    }

    func rename(_ box: StorageBox, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = boxes.firstIndex(where: { $0.id == box.id }) else { return }
        boxes[index].displayName = trimmed
        save()
    }

    func remove(_ box: StorageBox) { // doesn't touch anything on the actual server, just forgets it locally
        boxes.removeAll { $0.id == box.id }
        try? KeychainStore.deletePassword(host: box.host, account: box.username)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        boxes.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            boxes = try JSONDecoder().decode([StorageBox].self, from: data)
        } catch {
            logger.error("failed to read boxes.json: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(boxes).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("failed to write boxes.json: \(error.localizedDescription)")
        }
    }
}

struct FolderFavorite: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var boxID: UUID
    var segments: [String]
    var title: String

    var path: RemotePath { RemotePath(segments: segments) }
}

@MainActor
@Observable
final class FolderFavoriteStore {
    private(set) var favorites: [FolderFavorite] = []

    private let fileURL: URL
    private let logger = Logger(subsystem: "de.silxnt.StorageBoxManager", category: "Favorites")

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("StorageBoxManager", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.fileURL = support.appendingPathComponent("favorites.json")
        }
        load()
    }

    func favorites(for boxID: StorageBox.ID) -> [FolderFavorite] {
        favorites.filter { $0.boxID == boxID }
    }

    func contains(boxID: StorageBox.ID, path: RemotePath) -> Bool {
        favorites.contains { $0.boxID == boxID && $0.segments == path.segments }
    }

    func toggle(boxID: StorageBox.ID, path: RemotePath, title: String) {
        if let existing = favorites.first(where: { $0.boxID == boxID && $0.segments == path.segments }) {
            remove(existing)
        } else {
            favorites.append(
                FolderFavorite(id: UUID(), boxID: boxID, segments: path.segments, title: title)
            )
            save()
        }
    }

    func remove(_ favorite: FolderFavorite) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    func prune(validBoxIDs: Set<UUID>) {
        let before = favorites.count
        favorites.removeAll { !validBoxIDs.contains($0.boxID) }
        if favorites.count != before { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            favorites = try JSONDecoder().decode([FolderFavorite].self, from: data)
        } catch {
            logger.error("failed to read favorites.json: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(favorites).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("failed to write favorites.json: \(error.localizedDescription)")
        }
    }
}

enum LastPathStore {
    private static func key(for boxID: UUID) -> String {
        "lastPath.\(boxID.uuidString)"
    }

    static func load(for boxID: UUID) -> RemotePath? {
        guard let segments = UserDefaults.standard.stringArray(forKey: key(for: boxID)) else { return nil }
        return RemotePath(segments: segments)
    }

    static func save(_ path: RemotePath, for boxID: UUID) {
        UserDefaults.standard.set(path.segments, forKey: key(for: boxID))
    }
}
