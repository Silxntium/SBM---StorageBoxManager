import Foundation
import Observation

enum BoxEditor: Identifiable, Hashable {
    case new
    case existing(StorageBox.ID)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let id): id.uuidString
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let store = BoxStore()
    let transfers = TransferQueue()
    let favorites = FolderFavoriteStore()
    var selectedBoxID: StorageBox.ID?
    var boxEditor: BoxEditor?
    var showsTransfersInspector = false
    var showsSidebar = true
    var pendingFolder: RemotePath?
    var showsSettings = false
    var previewRequest: QuickLookRequest?

    var selectedBox: StorageBox? {
        guard let selectedBoxID else { return nil }
        return store.boxes.first { $0.id == selectedBoxID }
    }

    init() {
        // macOS shows list and browser side by side, so opening straight into a box is free.
        // On iPhone a selection pushes a screen, and landing inside a box skips the list.
        #if os(macOS)
        selectedBoxID = store.boxes.first?.id
        #endif
        favorites.prune(validBoxIDs: Set(store.boxes.map(\.id)))
    }

    func openFavorite(_ favorite: FolderFavorite) {
        selectedBoxID = favorite.boxID
        pendingFolder = favorite.path
    }

    func backend(for box: StorageBox) throws -> any StorageBackend {
        guard let password = try KeychainStore.password(host: box.host, account: box.username),
              !password.isEmpty
        else {
            throw BackendError.missingPassword
        }
        return try WebDAVBackend(box: box, password: password)
    }

    // macOS asks for a download folder the first time and returns nil if the panel got
    // cancelled; iOS always has one (the app's Documents folder).
    func resolveDownloadFolder() -> URL? {
        #if os(macOS)
        DownloadFolderStore.resolve() ?? DownloadFolderStore.promptForFolder()
        #else
        DownloadFolderStore.resolve()
        #endif
    }

    // macOS floats a Quick Look panel over whatever is frontmost; iOS drives a sheet from here.
    func presentPreview(url: URL, title: String) {
        #if os(macOS)
        QuickLookPreview.present(url: url, title: title)
        #else
        previewRequest = QuickLookRequest(url: url, title: title)
        #endif
    }

    // "Download and Open" hands the file to another app on macOS. iOS has no such thing, so it
    // previews instead - Quick Look's share button covers passing it on.
    func openDownloaded(url: URL, title: String) {
        #if os(macOS)
        openInDefaultApp(url)
        #else
        presentPreview(url: url, title: title)
        #endif
    }

    // people paste the full "Connect to Server" URL from Finder here more often than not
    static func normalizeHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://", "webdav://", "webdavs://", "smb://", "sftp://"]
        where value.hasPrefix(scheme) {
            value.removeFirst(scheme.count)
            break
        }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        return value
    }

    // hetzner username is just the first bit of the hostname (u123456.your-storagebox.de -> u123456)
    static func suggestedUsername(forHost host: String) -> String {
        String(host.split(separator: ".").first ?? "")
    }
}
