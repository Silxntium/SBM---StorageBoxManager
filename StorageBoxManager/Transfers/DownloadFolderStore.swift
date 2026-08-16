import AppKit
import Foundation

// a plain path string is useless after relaunch in the sandbox - need the security-scoped
// bookmark to actually keep write access
enum DownloadFolderStore {
    private static let defaultsKey = "downloadFolderBookmark"

    static func save(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: defaultsKey)
    }

    static func resolve() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return nil
        }

        if isStale { try? save(url) }
        return url
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    @MainActor
    static func promptForFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Download Folder")
        panel.message = String(localized: "Choose the folder downloaded files should go into.")
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try? save(url)
        return url
    }

    @MainActor
    static func promptForUploadFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Upload Files")
        panel.prompt = String(localized: "Upload")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    // "file.txt" -> "file 2.txt" -> "file 3.txt" etc, same as Finder does it
    static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else {
            return candidate
        }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 2...999 {
            let suffixed = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let next = folder.appendingPathComponent(suffixed)
            if !FileManager.default.fileExists(atPath: next.path(percentEncoded: false)) {
                return next
            }
        }
        return folder.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)")
    }
}
