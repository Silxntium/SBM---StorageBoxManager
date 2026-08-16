import Foundation
import Observation

/// Runs uploads and downloads with a bounded amount of concurrency.
///
/// Three at a time: enough to keep the link busy, few enough that a storage box does not start
/// refusing connections when a folder full of files is dropped in at once.
@MainActor
@Observable
final class TransferQueue {
    private(set) var transfers: [Transfer] = []

    private let maxConcurrent = 3
    private var running: [Transfer.ID: Task<Void, Never>] = [:]
    private var jobs: [Transfer.ID: Job] = [:]

    private struct Job {
        let transfer: Transfer
        let body: @Sendable (@escaping @Sendable (Int64, Int64) -> Void) async throws -> Void
        let onSuccess: @MainActor () -> Void
    }

    var activeCount: Int {
        transfers.count { $0.state.isActive }
    }

    var hasFinishedEntries: Bool {
        transfers.contains { !$0.state.isActive }
    }

    // MARK: - Enqueueing

    func upload(
        _ localURL: URL,
        to path: RemotePath,
        backend: any StorageBackend,
        boxName: String,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        let destination = path.appending(localURL.lastPathComponent)
        let transfer = Transfer(kind: .upload, name: localURL.lastPathComponent, boxName: boxName)
        enqueue(
            Job(
                transfer: transfer,
                body: { progress in
                    try await backend.upload(localURL, to: destination, onProgress: progress)
                },
                onSuccess: onSuccess
            )
        )
    }

    func download(
        _ item: RemoteItem,
        to localURL: URL,
        backend: any StorageBackend,
        boxName: String,
        // The folder the user picked lives outside the sandbox; access has to be claimed for
        // the whole transfer and released again afterwards.
        securityScopedRoot: URL?,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        let transfer = Transfer(kind: .download, name: item.name, boxName: boxName)
        let path = item.path
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
    }

    private func start(_ job: Job) {
        let transfer = job.transfer
        transfer.state = .running

        let throttle = ProgressThrottle()
        let report: @Sendable (Int64, Int64) -> Void = { done, total in
            guard throttle.shouldReport(done: done, total: total) else { return }
            Task { @MainActor in
                transfer.bytesDone = done
                transfer.bytesTotal = total
            }
        }

        running[transfer.id] = Task { [weak self] in
            do {
                try await job.body(report)
                transfer.state = .finished
                if transfer.bytesTotal > 0 { transfer.bytesDone = transfer.bytesTotal }
                job.onSuccess()
            } catch is CancellationError {
                transfer.state = .cancelled
            } catch {
                transfer.state = .failed(BrowserModel.describe(error))
            }
            self?.completed(transfer.id)
        }
    }

    private func completed(_ id: Transfer.ID) {
        running.removeValue(forKey: id)
        jobs.removeValue(forKey: id)
        pump()
    }

    // MARK: - Control

    func cancel(_ id: Transfer.ID) {
        if let task = running[id] {
            task.cancel()
        } else if let transfer = transfers.first(where: { $0.id == id }), transfer.state == .waiting {
            // Never started, so there is no task to cancel — mark it directly.
            transfer.state = .cancelled
            jobs.removeValue(forKey: id)
        }
    }

    func cancelAll() {
        for transfer in transfers where transfer.state.isActive {
            cancel(transfer.id)
        }
    }

    func clearFinished() {
        transfers.removeAll { !$0.state.isActive }
    }
}
