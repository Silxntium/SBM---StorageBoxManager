import Foundation

/// Streams a GET response straight into the destination file.
///
/// A data task with a delegate is used instead of `URLSession.download(for:delegate:)` for two
/// reasons: bytes land directly in the location the user picked, so nothing has to be moved
/// out of a temporary directory afterwards, and progress plus cancellation are available
/// without mixing a task-level delegate into the async download API, where the delegate and
/// the awaited result both want to own the finished file.
final class StreamingDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let pathDescription: String
    private let onProgress: @Sendable (Int64, Int64) -> Void

    private let lock = NSLock()
    private var handle: FileHandle?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var recordedFailure: (any Error)?
    private var receivedBytes: Int64 = 0
    private var expectedBytes: Int64 = -1
    private var isFinished = false
    /// Set by `cancel()` even before the URL task exists, so a cancellation that arrives
    /// during setup is not lost.
    private var cancelRequested = false

    init(
        destination: URL,
        pathDescription: String,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) {
        self.destination = destination
        self.pathDescription = pathDescription
        self.onProgress = onProgress
    }

    func run(request: URLRequest, configuration: URLSessionConfiguration) async throws {
        try Task.checkCancellation()

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        guard fileManager.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
            throw BackendError.transport("Zieldatei „\(destination.lastPathComponent)“ konnte nicht angelegt werden")
        }
        do {
            let handle = try FileHandle(forWritingTo: destination)
            lock.withLock { self.handle = handle }
        } catch {
            throw BackendError.transport(error.localizedDescription)
        }

        // A serial delegate queue means the callbacks below never run concurrently with
        // each other; the lock only guards the handoff to and from the async caller.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "de.silxnt.StorageBoxManager.download"

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }

        let dataTask = session.dataTask(with: request)
        lock.withLock { self.task = dataTask }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let wasCancelledDuringSetup: Bool = lock.withLock {
                    self.continuation = continuation
                    return cancelRequested
                }
                // Cancelling a task that has not been resumed yet produces no delegate
                // callback, so that case is completed here instead of waiting forever.
                if wasCancelledDuringSetup {
                    finish(with: URLError(.cancelled))
                } else {
                    dataTask.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        let task: URLSessionDataTask? = lock.withLock {
            cancelRequested = true
            return self.task
        }
        task?.cancel()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            record(BackendError.malformedResponse("keine HTTP-Antwort"))
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            record(BackendError.from(status: http.statusCode, path: pathDescription))
            completionHandler(.cancel)
            return
        }

        let expected = http.expectedContentLength
        lock.withLock { expectedBytes = expected }
        onProgress(0, expected)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let progress: (Int64, Int64)?
        do {
            progress = try lock.withLock {
                guard let handle else { return nil }
                try handle.write(contentsOf: data)
                receivedBytes += Int64(data.count)
                return (receivedBytes, expectedBytes)
            }
        } catch {
            // Typically a full disk. Cancelling makes didCompleteWithError fire, which then
            // reports this recorded error rather than the cancellation.
            record(BackendError.transport(error.localizedDescription))
            dataTask.cancel()
            return
        }
        if let progress { onProgress(progress.0, progress.1) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(with: error)
    }

    // MARK: - Completion

    private func record(_ error: any Error) {
        lock.withLock {
            if recordedFailure == nil { recordedFailure = error }
        }
    }

    private func finish(with error: (any Error)?) {
        let outcome: (continuation: CheckedContinuation<Void, any Error>?, failure: (any Error)?)? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true

            let continuation = self.continuation
            self.continuation = nil
            try? handle?.close()
            handle = nil

            return (continuation, recordedFailure)
        }
        guard let outcome else { return }

        // A recorded failure always wins: when a bad status or a write error cancelled the
        // task, `error` is only the cancellation that followed from it.
        let finalError: (any Error)?
        if let failure = outcome.failure {
            finalError = failure
        } else if let urlError = error as? URLError, urlError.code == .cancelled {
            finalError = CancellationError()
        } else if let error {
            finalError = BackendError.transport(error.localizedDescription)
        } else {
            finalError = nil
        }

        if let finalError {
            try? FileManager.default.removeItem(at: destination)
            outcome.continuation?.resume(throwing: finalError)
        } else {
            outcome.continuation?.resume()
        }
    }
}
