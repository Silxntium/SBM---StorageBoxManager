import Foundation
import Observation

@MainActor
@Observable
final class TransferQueue {
    static let deleteSourceAfterUploadKey = "deleteSourceAfterUpload"
    static let moveSourceToTrashKey = "moveSourceToTrash"
    static let removeEmptySourceFoldersKey = "removeEmptySourceFolders"
    static let concurrentTransferCountKey = "concurrentTransferCount"
    static let uploadConflictPolicyKey = "uploadConflictPolicy"

    private(set) var transfers: [Transfer] = []

    private var maxConcurrent: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.concurrentTransferCountKey)
        return min(max(stored == 0 ? 3 : stored, 1), 6)
    }
    private var running: [Transfer.ID: Task<Void, Never>] = [:]
    private var jobs: [Transfer.ID: Job] = [:]
    private let activity = TransferActivity() // keeps iOS from suspending us mid-transfer

    private struct Job {
        let transfer: Transfer
        let body: @Sendable (@escaping @Sendable (Int64, Int64) -> Void) async throws -> Void
        let onSuccess: @MainActor () -> Void
    }

    var activeCount: Int {
        transfers.count { $0.state.isActive }
    }

    var hasFinishedEntries: Bool {
        transfers.contains { $0.state == .finished }
    }

    var hasRetryableTransfers: Bool {
        transfers.contains { $0.canRetry }
    }

    // MARK: - Enqueueing

    func upload(
        _ localURL: URL,
        to destination: RemotePath,
        backend: any StorageBackend,
        boxID: StorageBox.ID,
        boxName: String,
        displayName: String? = nil,
        securityScopedRoot: URL? = nil,
        deleteSourceAfterUpload: Bool = false,
        moveSourceToTrash: Bool = false,
        removeEmptySourceFolders: Bool = false,
        sourceFolderRoot: URL? = nil,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        let transfer = Transfer(
            kind: .upload,
            name: displayName ?? destination.name,
            boxName: boxName,
            boxID: boxID
        )
        enqueue(
            Job(
                transfer: transfer,
                body: { progress in
                    let claimed = securityScopedRoot?.startAccessingSecurityScopedResource() ?? false
                    defer { if claimed { securityScopedRoot?.stopAccessingSecurityScopedResource() } }
                    let cleanupSnapshot: (size: Int64, modificationDate: Date?)?
                    if deleteSourceAfterUpload {
                        let values = try localURL.resourceValues(
                            forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
                        )
                        guard values.isRegularFile == true, let size = values.fileSize else {
                            throw SourceCleanupError.sourceIsNotRegularFile
                        }
                        cleanupSnapshot = (Int64(size), values.contentModificationDate)
                    } else {
                        cleanupSnapshot = nil
                    }
                    if let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                        progress(0, Int64(size))
                    }
                    try await backend.upload(localURL, to: destination, onProgress: progress)

                    if let cleanupSnapshot {
                        await MainActor.run { transfer.beginPhase(.verifying) }
                        try await Self.verifyAndDeleteSource(
                            localURL,
                            originalSize: cleanupSnapshot.size,
                            originalModificationDate: cleanupSnapshot.modificationDate,
                            destination: destination,
                            backend: backend,
                            moveToTrash: moveSourceToTrash,
                            onReadyToClean: {
                                await MainActor.run {
                                    transfer.beginPhase(.cleaning(moveToTrash: moveSourceToTrash))
                                }
                            }
                        )
                        if removeEmptySourceFolders, let sourceFolderRoot {
                            try Self.cleanupEmptyFolders(at: sourceFolderRoot, moveToTrash: moveSourceToTrash)
                        }
                    }
                },
                onSuccess: onSuccess
            )
        )
    }

    nonisolated private static func verifyAndDeleteSource(
        _ localURL: URL,
        originalSize: Int64,
        originalModificationDate: Date?,
        destination: RemotePath,
        backend: any StorageBackend,
        moveToTrash: Bool,
        onReadyToClean: @escaping @Sendable () async -> Void
    ) async throws {
        guard let remoteSize = try await backend.resourceSize(at: destination) else {
            throw SourceCleanupError.remoteSizeUnavailable
        }
        guard remoteSize == originalSize else {
            throw SourceCleanupError.sizeMismatch(local: originalSize, remote: remoteSize)
        }

        let currentValues = try localURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        )
        guard currentValues.isRegularFile == true,
              currentValues.fileSize.map(Int64.init) == originalSize,
              currentValues.contentModificationDate == originalModificationDate
        else {
            throw SourceCleanupError.sourceChanged
        }

        await onReadyToClean()
        try cleanupItem(at: localURL, moveToTrash: moveToTrash)
    }

    nonisolated private static func cleanupItem(at url: URL, moveToTrash: Bool) throws {
        #if os(macOS)
        if moveToTrash {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return
        }
        #endif
        try FileManager.default.removeItem(at: url)
    }

    nonisolated private static func cleanupEmptyFolders(at root: URL, moveToTrash: Bool) throws {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for child in contents where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            try cleanupEmptyFolders(at: child, moveToTrash: false)
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
        if remaining.isEmpty {
            try cleanupItem(at: root, moveToTrash: moveToTrash)
        }
    }

    func download(
        path: RemotePath,
        to localURL: URL,
        backend: any StorageBackend,
        boxID: StorageBox.ID,
        boxName: String,
        displayName: String? = nil,
        securityScopedRoot: URL?, // outside the sandbox, gotta claim/release access around the transfer
        kind: Transfer.Kind = .download,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        let transfer = Transfer(
            kind: kind,
            name: displayName ?? path.name,
            boxName: boxName,
            boxID: boxID
        )
        enqueue(
            Job(
                transfer: transfer,
                body: { progress in
                    let claimed = securityScopedRoot?.startAccessingSecurityScopedResource() ?? false
                    defer { if claimed { securityScopedRoot?.stopAccessingSecurityScopedResource() } }
                    try await backend.download(path, to: localURL, onProgress: progress)
                },
                onSuccess: onSuccess
            )
        )
    }

    private func enqueue(_ job: Job) {
        transfers.append(job.transfer)
        jobs[job.transfer.id] = job
        pump()
    }

    nonisolated static func cleanupEmptyUploadFolders(_ roots: [URL], moveToTrash: Bool) throws {
        for root in roots {
            let claimed = root.startAccessingSecurityScopedResource()
            defer { if claimed { root.stopAccessingSecurityScopedResource() } }
            try cleanupEmptyFolders(at: root, moveToTrash: moveToTrash)
        }
    }

    // MARK: - Scheduling

    private func pump() {
        while running.count < maxConcurrent,
              let next = transfers.first(where: { $0.state == .waiting }),
              let job = jobs[next.id] {
            start(job)
        }
        activity.update(
            isBusy: activeCount > 0,
            hasActiveUploads: transfers.contains { $0.kind == .upload && $0.state.isActive }
        )
    }

    private func start(_ job: Job) {
        let transfer = job.transfer
        transfer.state = .running

        let throttle = ProgressThrottle()
        let report: @Sendable (Int64, Int64) -> Void = { done, total in
            guard throttle.shouldReport(done: done, total: total) else { return }
            Task { @MainActor in
                transfer.recordProgress(done: done, total: total)
            }
        }

        running[transfer.id] = Task { [weak self] in
            do {
                try await job.body(report)
                transfer.state = .finished
                if transfer.bytesTotal > 0 { transfer.bytesDone = transfer.bytesTotal }
                transfer.bytesPerSecond = nil
                job.onSuccess()
                self?.completed(transfer.id, succeeded: true)
            } catch is CancellationError {
                transfer.state = .cancelled
                transfer.bytesPerSecond = nil
                self?.completed(transfer.id, succeeded: false)
            } catch {
                transfer.state = .failed(BrowserModel.describe(error))
                transfer.bytesPerSecond = nil
                self?.completed(transfer.id, succeeded: false)
            }
        }
    }

    private func completed(_ id: Transfer.ID, succeeded: Bool) {
        running.removeValue(forKey: id)
        if succeeded {
            jobs.removeValue(forKey: id)
        }
        pump()
    }

    // MARK: - Control

    func retry(_ id: Transfer.ID) {
        guard let transfer = transfers.first(where: { $0.id == id }), transfer.canRetry, jobs[id] != nil else { return }
        transfer.prepareForRetry()
        pump()
    }

    func retryAllFailed() {
        for transfer in transfers where transfer.canRetry {
            retry(transfer.id)
        }
    }

    func cancel(_ id: Transfer.ID) {
        if let task = running[id] {
            task.cancel()
        } else if let transfer = transfers.first(where: { $0.id == id }), transfer.state == .waiting {
            transfer.state = .cancelled
            pump()
        }
    }

    func cancelAll() {
        for transfer in transfers where transfer.state.isActive {
            cancel(transfer.id)
        }
    }

    func clearFinished() {
        let finishedIDs = Set(transfers.filter { $0.state == .finished }.map(\.id))
        transfers.removeAll { $0.state == .finished }
        for id in finishedIDs {
            jobs.removeValue(forKey: id)
        }
    }
}

private enum SourceCleanupError: LocalizedError {
    case sourceIsNotRegularFile
    case remoteSizeUnavailable
    case sizeMismatch(local: Int64, remote: Int64)
    case sourceChanged

    var errorDescription: String? {
        switch self {
        case .sourceIsNotRegularFile:
            String(localized: "The source is not a regular file, so it was not deleted.")
        case .remoteSizeUnavailable:
            String(localized: "The server could not confirm the uploaded file size. The source was not deleted.")
        case .sizeMismatch(let local, let remote):
            String(localized: "The uploaded file is \(remote.formatted(.byteCount(style: .file))), but the source is \(local.formatted(.byteCount(style: .file))). The source was not deleted.")
        case .sourceChanged:
            String(localized: "The source file changed during the upload, so it was not deleted.")
        }
    }
}
