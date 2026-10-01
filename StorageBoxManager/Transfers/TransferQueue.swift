import Foundation
import Observation

@MainActor
@Observable
final class TransferQueue {
    private(set) var transfers: [Transfer] = []

    private let maxConcurrent = 3 // more than this and the box starts refusing connections on a big batch
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
                    if let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                        progress(0, Int64(size))
                    }
                    try await backend.upload(localURL, to: destination, onProgress: progress)
                },
                onSuccess: onSuccess
            )
        )
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

    // MARK: - Scheduling

    private func pump() {
        while running.count < maxConcurrent,
              let next = transfers.first(where: { $0.state == .waiting }),
              let job = jobs[next.id] {
            start(job)
        }
        activity.update(isBusy: activeCount > 0)
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
