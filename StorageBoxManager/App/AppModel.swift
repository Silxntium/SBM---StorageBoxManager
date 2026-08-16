import Foundation
import Observation

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

    // asks for a download folder the first time, nil if the panel got cancelled
    func resolveDownloadFolder() -> URL? {
        DownloadFolderStore.resolve() ?? DownloadFolderStore.promptForFolder()
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
