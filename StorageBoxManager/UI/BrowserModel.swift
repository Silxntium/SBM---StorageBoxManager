import Foundation
import Observation

@MainActor
@Observable
final class BrowserModel {
    let box: StorageBox

    private(set) var path: RemotePath = .root
    private(set) var items: [RemoteItem] = []
    private(set) var state: LoadState = .idle
    var selection: Set<RemoteItem.ID> = []
    var sortOrder: [KeyPathComparator<RemoteItem>] = [KeyPathComparator(\.name, order: .forward)]
    var alert: AlertMessage?

    // hide dotfiles like Finder does - mostly .DS_Store / ._ AppleDouble junk macOS creates
    // because WebDAV can't hold extended attributes
    var showsHiddenFiles: Bool {
        didSet { UserDefaults.standard.set(showsHiddenFiles, forKey: Self.hiddenFilesKey) }
    }

    private static let hiddenFilesKey = "showsHiddenFiles"

    private let backend: (any StorageBackend)?
    private let setupFailure: String?
    private let queue: TransferQueue
    private var cache: [RemotePath: [RemoteItem]] = [:] // per-session, so going back up a level is instant
    private var loadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct AlertMessage: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    init(box: StorageBox, model: AppModel) {
        self.box = box
        queue = model.transfers
        showsHiddenFiles = UserDefaults.standard.bool(forKey: Self.hiddenFilesKey)
        do {
            backend = try model.backend(for: box)
            setupFailure = nil
        } catch {
            backend = nil
            setupFailure = Self.describe(error)
        }
    }

    // MARK: - Derived

    var visibleItems: [RemoteItem] {
        showsHiddenFiles ? items : items.filter { !$0.name.hasPrefix(".") }
    }

    var hiddenItemCount: Int {
        items.count - visibleItems.count
    }

    // folders always first regardless of sort column, like every file browser does it
    var sortedItems: [RemoteItem] {
        visibleItems.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return sortOrder.compare(lhs, rhs) == .orderedAscending
        }
    }

    var selectedItems: [RemoteItem] {
        visibleItems.filter { selection.contains($0.id) }
    }

    var canGoUp: Bool { !path.isRoot }

    // MARK: - Navigation

    func navigate(to newPath: RemotePath) {
        guard newPath != path else { return }
        path = newPath
        selection = []
        reload(force: false)
    }

    func open(_ item: RemoteItem) {
        guard item.isDirectory else { return }
        navigate(to: item.path)
    }

    func goUp() {
        guard let parent = path.parent else { return }
        navigate(to: parent)
    }

    func refresh() {
        reload(force: true)
    }

    func reload(force: Bool) {
        loadTask?.cancel()

        if let setupFailure {
            state = .failed(setupFailure)
            return
        }
        guard let backend else { return }

        if !force, let cached = cache[path] {
            items = cached
            state = .loaded
            return
        }

        let target = path
        state = .loading
        items = []

        loadTask = Task { [weak self] in
            do {
                let listing = try await backend.list(target)
                guard !Task.isCancelled else { return }
                guard let self, self.path == target else { return }
                self.cache[target] = listing
                self.items = listing
                self.state = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                guard let self, self.path == target else { return }
                self.state = .failed(Self.describe(error))
            }
        }
    }

    // MARK: - Mutations

    func createFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let backend, validate(name: name, action: "New Folder") else { return }

        perform(title: "Couldn't Create Folder") {
            try await backend.createDirectory(at: self.path.appending(name))
        }
    }

    func rename(_ item: RemoteItem, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != item.name else { return }
        guard let backend, validate(name: name, action: "Rename") else { return }

        perform(title: "Rename Failed") {
            try await backend.move(
                from: item.path,
                to: item.path.renamed(to: name),
                isDirectory: item.isDirectory
            )
        }
    }

    func delete(_ targets: [RemoteItem]) {
        guard let backend, !targets.isEmpty else { return }

        perform(title: "Delete Failed") {
            // one at a time on purpose - box chokes if you fire off a bunch of DELETEs at once
            for target in targets {
                try await backend.delete(target.path, isDirectory: target.isDirectory)
            }
        }
    }

    // MARK: - Transfers

    // TODO: recursive folder upload would be nice, PUT is per-file only right now so we just skip dirs
    func upload(_ urls: [URL]) {
        guard let backend else { return }
        let target = path
        var skippedFolders: [String] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false),
                isDirectory: &isDirectory
            )
            guard exists else { continue }
            guard !isDirectory.boolValue else {
                skippedFolders.append(url.lastPathComponent)
                continue
            }

            queue.upload(url, to: target, backend: backend, boxName: box.resolvedName) { [weak self] in
                guard let self, self.path == target else { return }
                self.invalidateCache(for: target)
                self.scheduleRefresh()
            }
        }

        if !skippedFolders.isEmpty {
            alert = AlertMessage(
                title: "Folders Skipped",
                message: "\(skippedFolders.joined(separator: ", ")) — this version can only upload individual files."
            )
        }
    }

    func download(_ targets: [RemoteItem], to folder: URL) {
        guard let backend else { return }
        let files = targets.filter { !$0.isDirectory }

        for item in files {
            let destination = DownloadFolderStore.uniqueDestination(for: item.name, in: folder)
            queue.download(
                item,
                to: destination,
                backend: backend,
                boxName: box.resolvedName,
                securityScopedRoot: folder,
                onSuccess: {}
            )
        }

        if files.count != targets.count {
            alert = AlertMessage(
                title: "Folders Skipped",
                message: "This version can only download individual files, not whole folders."
            )
        }
    }

    // debounce - a batch of uploads finishing at once shouldn't trigger a reload each
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.reload(force: true)
        }
    }

    var storageBackend: (any StorageBackend)? { backend } // used by drag-out export, bypasses the queue

    private func perform(title: String, _ operation: @escaping () async throws -> Void) {
        Task { [weak self] in
            do {
                try await operation()
                self?.cache.removeValue(forKey: self?.path ?? .root)
                self?.reload(force: true)
            } catch is CancellationError {
                return
            } catch {
                self?.alert = AlertMessage(title: title, message: Self.describe(error))
                self?.reload(force: true)
            }
        }
    }

    private func validate(name: String, action: String) -> Bool {
        guard !name.isEmpty else {
            alert = AlertMessage(title: action, message: "The name can't be empty.")
            return false
        }
        guard !name.contains("/") else {
            alert = AlertMessage(title: action, message: "The name can't contain a slash.")
            return false
        }
        guard name != "." && name != ".." else {
            alert = AlertMessage(title: action, message: "\"\(name)\" isn't allowed as a name.")
            return false
        }
        return true
    }

    func invalidateCache(for target: RemotePath) {
        cache.removeValue(forKey: target)
    }

    static func describe(_ error: any Error) -> String {
        guard let backendError = error as? BackendError else { return error.localizedDescription }
        let description = backendError.errorDescription ?? "Unknown error"
        guard let suggestion = backendError.recoverySuggestion else { return description }
        return "\(description) \(suggestion)"
    }
}
