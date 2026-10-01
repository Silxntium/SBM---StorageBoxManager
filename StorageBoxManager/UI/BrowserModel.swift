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

    var searchText = ""
    var searchScope: SearchScope = .folder
    var kindFilter: KindCategory = .all
    var listingLayout: ListingLayout
    var foldersFirst: Bool
    var usesRelativeDates: Bool
    var sortField: SortField = .name
    var sortReversed = false
    private(set) var quota: StorageQuota?
    var conflictPrompt: ConflictPrompt?

    private(set) var deepResults: [RemoteItem] = []
    private(set) var isDeepSearching = false
    private(set) var searchedFolderCount = 0

    // hide dotfiles like Finder does - mostly .DS_Store / ._ AppleDouble junk macOS creates
    // because WebDAV can't hold extended attributes
    var showsHiddenFiles: Bool {
        didSet { UserDefaults.standard.set(showsHiddenFiles, forKey: Self.hiddenFilesKey) }
    }

    private static let hiddenFilesKey = "showsHiddenFiles"
    private static let foldersFirstKey = "foldersFirst"
    private static let relativeDatesKey = "relativeDates"
    private static let layoutKey = "listingLayout"
    private static let sortFieldKey = "sortField"
    private static let sortReversedKey = "sortReversed"

    private let backend: (any StorageBackend)?
    private let appModel: AppModel // Quick Look and "open" go through the app, not AppKit
    private let setupFailure: String?
    private let queue: TransferQueue
    private var cache: [RemotePath: [RemoteItem]] = [:] // per-session, so going back up a level is instant
    private var backStack: [RemotePath] = []
    private var forwardStack: [RemotePath] = []
    private var loadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var conflictContinuation: CheckedContinuation<(ConflictDecision, Bool), Never>?
    private var rootQuota: StorageQuota?

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

    init(box: StorageBox, model: AppModel, initialPath: RemotePath? = nil) {
        self.box = box
        appModel = model
        queue = model.transfers
        showsHiddenFiles = UserDefaults.standard.bool(forKey: Self.hiddenFilesKey)
        foldersFirst = UserDefaults.standard.object(forKey: Self.foldersFirstKey) as? Bool ?? true
        usesRelativeDates = UserDefaults.standard.object(forKey: Self.relativeDatesKey) as? Bool ?? true
        listingLayout = ListingLayout(rawValue: UserDefaults.standard.string(forKey: Self.layoutKey) ?? "") ?? .list
        sortField = SortField(rawValue: UserDefaults.standard.string(forKey: Self.sortFieldKey) ?? "") ?? .name
        sortReversed = UserDefaults.standard.bool(forKey: Self.sortReversedKey)
        do {
            backend = try model.backend(for: box)
            setupFailure = nil
        } catch {
            backend = nil
            setupFailure = Self.describe(error)
        }
        applySort(field: sortField, reversed: sortReversed, persist: false)
        path = initialPath ?? LastPathStore.load(for: box.id) ?? .root
    }

    // MARK: - Derived

    var visibleItems: [RemoteItem] {
        showsHiddenFiles ? items : items.filter { !$0.name.hasPrefix(".") }
    }

    var hiddenItemCount: Int {
        items.count - visibleItems.count
    }

    var isDeepSearchActive: Bool {
        searchScope == .subtree && !normalizedQuery.isEmpty
    }

    var displayedItems: [RemoteItem] {
        let source: [RemoteItem]
        if isDeepSearchActive {
            source = deepResults.filter { kindFilter.matches($0) && matchesVisibility($0) }
        } else {
            source = visibleItems.filter { kindFilter.matches($0) && $0.matches(search: normalizedQuery) }
        }
        return sorted(source)
    }

    var selectedItems: [RemoteItem] {
        displayedItems.filter { selection.contains($0.id) }
    }

    var canGoUp: Bool { !path.isRoot }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var selectedSize: Int64 {
        selectedItems.compactMap(\.size).reduce(0, +)
    }

    var visibleSize: Int64 {
        displayedItems.compactMap(\.size).reduce(0, +)
    }

    var statusSummary: String {
        let shown = displayedItems
        if isDeepSearching {
            let found = shown.count
            return String(localized: "Searching… \(found) found in \(searchedFolderCount) folders")
        }
        if !normalizedQuery.isEmpty || kindFilter != .all {
            if selectedItems.isEmpty {
                return String(localized: "\(shown.count) of \(visibleItems.count)")
            }
            return String(localized: "\(selectedItems.count) of \(shown.count) selected")
        }
        if selectedItems.isEmpty {
            let count = String(localized: "\(shown.count) items")
            if visibleSize > 0 {
                return "\(count) (\(visibleSize.formatted(.byteCount(style: .file))))"
            }
            return count
        }
        if selectedItems.count == 1, let item = selectedItems.first {
            if item.isDirectory {
                return String(localized: "1 folder selected")
            }
            return String(localized: "1 item selected (\(item.formattedSize))")
        }
        let selected = String(localized: "\(selectedItems.count) selected")
        if selectedSize > 0 {
            return "\(selected) (\(selectedSize.formatted(.byteCount(style: .file))))"
        }
        return selected
    }

    var canQuickLook: Bool {
        selectedItems.contains { !$0.isDirectory }
    }

    var canDuplicate: Bool {
        selectedItems.count == 1
    }

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Navigation

    func navigate(to newPath: RemotePath, recordHistory: Bool = true) {
        guard newPath != path else { return }
        if recordHistory {
            backStack.append(path)
            forwardStack.removeAll()
        }
        path = newPath
        selection = []
        clearDeepSearch()
        LastPathStore.save(path, for: box.id)
        reload(force: false)
    }

    func open(_ item: RemoteItem) {
        if item.isDirectory {
            navigate(to: item.path)
        } else {
            preview(item)
        }
    }

    func goUp() {
        guard let parent = path.parent else { return }
        navigate(to: parent)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(path)
        navigate(to: previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(path)
        navigate(to: next, recordHistory: false)
    }

    func goToFolder(typed raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("~") { value.removeFirst() }
        navigate(to: RemotePath(href: value.isEmpty ? "/" : value))
    }

    func reveal(_ item: RemoteItem) {
        let parent = item.path.parent ?? .root
        searchText = ""
        searchScope = .folder
        clearDeepSearch()
        navigate(to: parent)
        selection = [item.id]
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
        // keep the current listing while a refresh is in flight so the table doesn't flash empty
        if let cached = cache[target] {
            items = cached
        } else {
            items = []
        }

        loadTask = Task { [weak self] in
            do {
                let listing = try await backend.inspect(target)
                guard !Task.isCancelled else { return }
                guard let self, self.path == target else { return }
                self.cache[target] = listing.items
                self.items = listing.items
                if let listingQuota = listing.quota {
                    self.quota = listingQuota
                    if target.isRoot { self.rootQuota = listingQuota }
                } else if let rootQuota {
                    self.quota = rootQuota
                } else if !target.isRoot {
                    if let rootListing = try? await backend.inspect(.root) {
                        self.rootQuota = rootListing.quota
                        self.quota = rootListing.quota
                    }
                }
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

    // MARK: - Sorting / layout

    func applySort(field: SortField, reversed: Bool? = nil, persist: Bool = true) {
        if let reversed {
            sortReversed = reversed
        } else if sortField == field {
            sortReversed.toggle()
        } else {
            sortReversed = false
        }
        sortField = field
        let order: SortOrder = sortReversed ? .reverse : .forward
        switch field {
        case .name:
            sortOrder = [KeyPathComparator(\.name, order: order)]
        case .modified:
            sortOrder = [KeyPathComparator(\.sortDate, order: order)]
        case .size:
            sortOrder = [KeyPathComparator(\.sortSize, order: order)]
        case .kind:
            sortOrder = [KeyPathComparator(\.kindDescription, order: order)]
        }
        if persist { persistDisplayPreferences() }
    }

    func adoptSortOrder(_ comparators: [KeyPathComparator<RemoteItem>]) {
        guard let first = comparators.first else { return }
        let reversed = first.order == .reverse
        let field = sortField(matching: first) ?? sortField
        guard field != sortField || reversed != sortReversed else { return }
        sortField = field
        sortReversed = reversed
        persistDisplayPreferences()
    }

    private func sortField(matching comparator: KeyPathComparator<RemoteItem>) -> SortField? {
        let order = comparator.order
        let candidates: [(SortField, KeyPathComparator<RemoteItem>)] = [
            (.name, KeyPathComparator(\.name, order: order)),
            (.modified, KeyPathComparator(\.sortDate, order: order)),
            (.size, KeyPathComparator(\.sortSize, order: order)),
            (.kind, KeyPathComparator(\.kindDescription, order: order)),
        ]
        return candidates.first(where: { $0.1 == comparator })?.0
    }

    func setLayout(_ layout: ListingLayout) {
        listingLayout = layout
        persistDisplayPreferences()
    }

    func setFoldersFirst(_ enabled: Bool) {
        foldersFirst = enabled
        persistDisplayPreferences()
    }

    func setRelativeDates(_ enabled: Bool) {
        usesRelativeDates = enabled
        persistDisplayPreferences()
    }

    // MARK: - Search

    func scheduleSearch() {
        searchTask?.cancel()
        guard isDeepSearchActive else {
            clearDeepSearch()
            return
        }

        let query = normalizedQuery
        let root = path
        let filter = kindFilter
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await self?.walk(from: root, query: query, filter: filter)
        }
    }

    func selectAll() {
        selection = Set(displayedItems.map(\.id))
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

    func duplicate(_ item: RemoteItem) {
        guard let backend else { return }
        let destination = item.path.renamed(to: unusedCopyName(for: item))
        perform(title: "Couldn't Duplicate") {
            try await backend.copy(from: item.path, to: destination, isDirectory: item.isDirectory)
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

    func upload(_ urls: [URL]) {
        guard let backend else { return }
        let target = path
        var directories: [RemotePath] = []
        var files: [PlannedUpload] = []

        for url in urls {
            let claimed = url.startAccessingSecurityScopedResource()
            defer { if claimed { url.stopAccessingSecurityScopedResource() } }
            collectUploads(from: url, remoteParent: target, root: url, relative: [], directories: &directories, files: &files)
        }

        var seen = Set<RemotePath>()
        let uniqueDirectories = directories
            .filter { seen.insert($0).inserted }
            .sorted { $0.segments.count < $1.segments.count }

        Task { [weak self] in
            guard let self else { return }
            var folderError: (any Error)?
            for directory in uniqueDirectories {
                do {
                    try await backend.createDirectory(at: directory)
                } catch let error as BackendError {
                    if case .alreadyExists = error { continue }
                    folderError = error
                } catch is CancellationError {
                    return
                } catch {
                    folderError = error
                }
            }

            var namesByParent: [RemotePath: Set<String>] = [:]
            var applied: ConflictDecision?
            var uploads: [PlannedUpload] = []
            var replaceError: (any Error)?
            for file in files {
                let parent = file.destination.parent ?? .root
                if namesByParent[parent] == nil {
                    namesByParent[parent] = await remoteNames(at: parent, backend: backend)
                }
                var planned = file
                if namesByParent[parent]?.contains(file.destination.name) == true {
                    let localSize = (try? file.localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    if let remoteSize = try? await backend.resourceSize(at: file.destination), localSize > 0 {
                        if remoteSize == localSize {
                            continue
                        }
                        // same name, smaller remote body — almost certainly a previous interrupted upload
                        if remoteSize > 0, remoteSize < localSize {
                            uploads.append(planned)
                            continue
                        }
                    }
                    let decision = await resolveConflict(
                        name: file.destination.name,
                        message: "“\(file.displayName)” already exists on the box.",
                        applied: &applied
                    )
                    switch decision {
                    case .skip:
                        continue
                    case .replace:
                        do {
                            try await backend.delete(file.destination, isDirectory: false)
                        } catch let error as BackendError {
                            if case .notFound = error {
                                // already gone
                            } else {
                                replaceError = error
                                continue
                            }
                        } catch is CancellationError {
                            return
                        } catch {
                            replaceError = error
                            continue
                        }
                    case .keepBoth:
                        let newName = Self.unusedName(file.destination.name, among: namesByParent[parent] ?? [])
                        planned = PlannedUpload(
                            localURL: file.localURL,
                            destination: parent.appending(newName),
                            displayName: file.displayName,
                            root: file.root
                        )
                        namesByParent[parent]?.insert(newName)
                    }
                }
                uploads.append(planned)
            }

            for file in uploads {
                queue.upload(
                    file.localURL,
                    to: file.destination,
                    backend: backend,
                    boxID: box.id,
                    boxName: box.resolvedName,
                    displayName: file.displayName,
                    securityScopedRoot: file.root
                ) { [weak self] in
                    guard let self else { return }
                    self.invalidateCache(for: target)
                    if self.path == target || target.isAncestor(of: self.path) {
                        self.scheduleRefresh()
                    }
                }
            }

            if uploads.isEmpty, !uniqueDirectories.isEmpty {
                invalidateCache(for: target)
                scheduleRefresh()
            }

            if let folderError {
                alert = AlertMessage(title: "Couldn't Upload Folder", message: Self.describe(folderError))
            } else if let replaceError {
                alert = AlertMessage(title: "Couldn't Replace File", message: Self.describe(replaceError))
            }
        }
    }

    func download(_ targets: [RemoteItem], to folder: URL, openWhenDone: Bool = false) {
        guard let backend else { return }

        Task { [weak self] in
            guard let self else { return }
            var directories: [URL] = []
            var files: [PlannedDownload] = []
            do {
                for item in targets {
                    try await collectDownloads(
                        item: item,
                        localParent: folder,
                        relative: [],
                        backend: backend,
                        directories: &directories,
                        files: &files
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                alert = AlertMessage(title: "Couldn't Download Folder", message: Self.describe(error))
                return
            }

            var applied: ConflictDecision?
            var downloads: [PlannedDownload] = []
            for file in files {
                var planned = file
                let localSize = (try? file.destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                if FileManager.default.fileExists(atPath: file.destination.path(percentEncoded: false)) {
                    if let remoteSize = file.remoteSize, localSize > 0, localSize < remoteSize {
                        downloads.append(planned)
                        continue
                    }
                    if let remoteSize = file.remoteSize, localSize == remoteSize, localSize > 0 {
                        continue
                    }
                    let decision = await resolveConflict(
                        name: file.destination.lastPathComponent,
                        message: "“\(file.displayName)” already exists in the download folder.",
                        applied: &applied
                    )
                    switch decision {
                    case .skip:
                        continue
                    case .replace:
                        try? FileManager.default.removeItem(at: file.destination)
                    case .keepBoth:
                        planned = PlannedDownload(
                            path: file.path,
                            destination: DownloadFolderStore.uniqueDestination(
                                for: file.destination.lastPathComponent,
                                in: file.destination.deletingLastPathComponent()
                            ),
                            displayName: file.displayName,
                            remoteSize: file.remoteSize
                        )
                    }
                }
                downloads.append(planned)
            }

            for directory in directories {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            for file in downloads {
                queue.download(
                    path: file.path,
                    to: file.destination,
                    backend: backend,
                    boxID: box.id,
                    boxName: box.resolvedName,
                    displayName: file.displayName,
                    securityScopedRoot: folder,
                    onSuccess: { [appModel] in
                        if openWhenDone {
                            appModel.openDownloaded(url: file.destination, title: file.displayName)
                        }
                    }
                )
            }
        }
    }

    func preview(_ item: RemoteItem) {
        guard let backend, !item.isDirectory else { return }
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            alert = AlertMessage(title: "Couldn't Preview", message: error.localizedDescription)
            return
        }
        let destination = folder.appending(path: item.name, directoryHint: .notDirectory)
        queue.download(
            path: item.path,
            to: destination,
            backend: backend,
            boxID: box.id,
            boxName: box.resolvedName,
            securityScopedRoot: nil,
            kind: .preview,
            onSuccess: { [appModel] in
                appModel.presentPreview(url: destination, title: item.name)
            }
        )
    }

    func resolveConflictPrompt(_ decision: ConflictDecision, applyToAll: Bool) {
        conflictContinuation?.resume(returning: (decision, applyToAll))
        conflictContinuation = nil
        conflictPrompt = nil
    }

    func dismissConflictIfNeeded() {
        guard conflictContinuation != nil else { return }
        resolveConflictPrompt(.skip, applyToAll: false)
    }

    func previewSelection() {
        if let file = selectedItems.first(where: { !$0.isDirectory }) {
            preview(file)
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

    // MARK: - Private

    private struct PlannedUpload {
        let localURL: URL
        let destination: RemotePath
        let displayName: String
        let root: URL
    }

    private struct PlannedDownload {
        let path: RemotePath
        let destination: URL
        let displayName: String
        let remoteSize: Int64?
    }

    private func collectDownloads(
        item: RemoteItem,
        localParent: URL,
        relative: [String],
        backend: any StorageBackend,
        directories: inout [URL],
        files: inout [PlannedDownload]
    ) async throws {
        if item.isDirectory {
            let localDirectory = localParent.appendingPathComponent(item.name, isDirectory: true)
            directories.append(localDirectory)
            let children = try await backend.list(item.path)
            for child in children {
                try await collectDownloads(
                    item: child,
                    localParent: localDirectory,
                    relative: relative + [item.name],
                    backend: backend,
                    directories: &directories,
                    files: &files
                )
            }
            return
        }

        files.append(
            PlannedDownload(
                path: item.path,
                destination: localParent.appendingPathComponent(item.name, isDirectory: false),
                displayName: (relative + [item.name]).joined(separator: "/"),
                remoteSize: item.size
            )
        )
    }

    private func remoteNames(at parent: RemotePath, backend: any StorageBackend) async -> Set<String> {
        if parent == path {
            return Set(items.map(\.name))
        }
        if let cached = cache[parent] {
            return Set(cached.map(\.name))
        }
        return Set((try? await backend.list(parent))?.map(\.name) ?? [])
    }

    private func resolveConflict(
        name: String,
        message: String,
        applied: inout ConflictDecision?
    ) async -> ConflictDecision {
        if let applied { return applied }
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<(ConflictDecision, Bool), Never>) in
            conflictContinuation = continuation
            conflictPrompt = ConflictPrompt(name: name, message: message)
        }
        if result.1 { applied = result.0 }
        return result.0
    }

    static func unusedName(_ name: String, among existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        func composed(_ suffix: String) -> String {
            ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
        }
        var candidate = composed(" 2")
        var index = 3
        while existing.contains(candidate) {
            candidate = composed(" \(index)")
            index += 1
        }
        return candidate
    }

    private func collectUploads(
        from url: URL,
        remoteParent: RemotePath,
        root: URL,
        relative: [String],
        directories: inout [RemotePath],
        files: inout [PlannedUpload]
    ) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return }

        let name = url.lastPathComponent
        guard !Self.shouldSkipUploadName(name) else { return }

        var isDirectory = values?.isDirectory ?? false
        if values?.isDirectory == nil {
            var objcDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &objcDirectory) {
                isDirectory = objcDirectory.boolValue
            }
        }

        if isDirectory {
            let remoteDirectory = remoteParent.appending(name)
            directories.append(remoteDirectory)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )) ?? []
            for child in children {
                collectUploads(
                    from: child,
                    remoteParent: remoteDirectory,
                    root: root,
                    relative: relative + [name],
                    directories: &directories,
                    files: &files
                )
            }
            return
        }

        let destination = remoteParent.appending(name)
        files.append(
            PlannedUpload(
                localURL: url,
                destination: destination,
                displayName: (relative + [name]).joined(separator: "/"),
                root: root
            )
        )
    }

    private static func shouldSkipUploadName(_ name: String) -> Bool {
        name == ".DS_Store" || name == ".localized" || name.hasPrefix("._")
    }

    private func walk(from root: RemotePath, query: String, filter: KindCategory) async {
        isDeepSearching = true
        searchedFolderCount = 0
        deepResults = []
        var folders = [root]
        var seen: Set<RemotePath> = [root]

        while !folders.isEmpty {
            guard !Task.isCancelled else { return }
            let current = folders.removeFirst()
            let listing = await listing(for: current)
            searchedFolderCount += 1
            for item in listing {
                if matchesVisibility(item), item.matches(search: query), filter.matches(item) {
                    if !deepResults.contains(item) {
                        deepResults.append(item)
                    }
                }
                if item.isDirectory, seen.insert(item.path).inserted {
                    folders.append(item.path)
                }
            }
        }

        isDeepSearching = false
    }

    private func listing(for folder: RemotePath) async -> [RemoteItem] {
        if let cached = cache[folder] { return cached }
        guard let backend else { return [] }
        do {
            let items = try await backend.list(folder)
            cache[folder] = items
            return items
        } catch {
            return []
        }
    }

    private func clearDeepSearch() {
        searchTask?.cancel()
        isDeepSearching = false
        searchedFolderCount = 0
        deepResults = []
    }

    private func matchesVisibility(_ item: RemoteItem) -> Bool {
        showsHiddenFiles || !item.name.hasPrefix(".")
    }

    private func sorted(_ source: [RemoteItem]) -> [RemoteItem] {
        source.sorted { lhs, rhs in
            if foldersFirst, lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return sortOrder.compare(lhs, rhs) == .orderedAscending
        }
    }

    private func unusedCopyName(for item: RemoteItem) -> String {
        let ext = (item.name as NSString).pathExtension
        let base = (item.name as NSString).deletingPathExtension
        let names = Set(items.map(\.name))
        func composed(_ suffix: String) -> String {
            ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
        }
        var candidate = composed(" copy")
        var index = 2
        while names.contains(candidate) {
            candidate = composed(" copy \(index)")
            index += 1
        }
        return candidate
    }

    private func persistDisplayPreferences() {
        UserDefaults.standard.set(foldersFirst, forKey: Self.foldersFirstKey)
        UserDefaults.standard.set(usesRelativeDates, forKey: Self.relativeDatesKey)
        UserDefaults.standard.set(listingLayout.rawValue, forKey: Self.layoutKey)
        UserDefaults.standard.set(sortField.rawValue, forKey: Self.sortFieldKey)
        UserDefaults.standard.set(sortReversed, forKey: Self.sortReversedKey)
    }

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
