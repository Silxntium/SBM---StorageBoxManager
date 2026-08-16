import Foundation
import Observation

/// Root state: the configured boxes, which one is selected, and the factory that turns a box
/// plus its stored password into a live backend.
@MainActor
@Observable
final class AppModel {
    let store = BoxStore()
    let transfers = TransferQueue()
    var selectedBoxID: StorageBox.ID?

    var selectedBox: StorageBox? {
        guard let selectedBoxID else { return nil }
        return store.boxes.first { $0.id == selectedBoxID }
    }

    func backend(for box: StorageBox) throws -> any StorageBackend {
        guard let password = try KeychainStore.password(host: box.host, account: box.username),
              !password.isEmpty
        else {
            throw BackendError.missingPassword
        }
        return try WebDAVBackend(box: box, password: password)
    }

    /// The download folder, asking for one the first time it is needed. Returns nil if the
    /// user cancelled the panel.
    func resolveDownloadFolder() -> URL? {
        DownloadFolderStore.resolve() ?? DownloadFolderStore.promptForFolder()
    }

    /// Normalises whatever was pasted into the host field — a full WebDAV URL copied out of
    /// the Finder's "Connect to Server" sheet is the most likely input.
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

    /// A Hetzner storage box's username is the hostname's first label (`u650699`), so the
    /// username field can fill itself in.
    static func suggestedUsername(forHost host: String) -> String {
        String(host.split(separator: ".").first ?? "")
    }
}
