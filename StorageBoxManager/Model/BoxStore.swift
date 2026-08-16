import Foundation
import Observation
import OSLog

/// Persists the configured boxes as JSON in the app's Application Support directory.
/// Passwords never touch this file — only the username, which keys the keychain lookup.
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

    /// The core feature: give a box whatever name makes it recognisable.
    func rename(_ box: StorageBox, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = boxes.firstIndex(where: { $0.id == box.id }) else { return }
        boxes[index].displayName = trimmed
        save()
    }

    /// Removes the box and its stored password. The remote data is untouched.
    func remove(_ box: StorageBox) {
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
            logger.error("boxes.json konnte nicht gelesen werden: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(boxes).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("boxes.json konnte nicht geschrieben werden: \(error.localizedDescription)")
        }
    }
}
