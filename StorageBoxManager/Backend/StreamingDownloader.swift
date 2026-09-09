import Foundation

// data task + delegate instead of URLSession.download(for:delegate:) - writes straight to the
// destination the user picked instead of a temp dir we'd have to move out of afterwards, and
// this way progress/cancellation don't fight with the async download API over who owns the file
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
    private var startOffset: Int64 = 0
    private var isFinished = false
    private var cancelRequested = false // can get set before `task` even exists, see run()
    private var preservePartial = true

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

        var request = request
        let fileManager = FileManager.default
        let existing = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        if existing > 0 {
            startOffset = existing
            receivedBytes = existing
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
            let handle = try FileHandle(forWritingTo: destination)
            try handle.seekToEnd()
            lock.withLock { self.handle = handle }
        } else {
            try? fileManager.removeItem(at: destination)
            guard fileManager.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
                throw BackendError.transport("couldn't create destination file \"\(destination.lastPathComponent)\"")
            }
            do {
                let handle = try FileHandle(forWritingTo: destination)
                lock.withLock { self.handle = handle }
            } catch {
                throw BackendError.transport(error.localizedDescription)
            }
        }

        // serial queue -> delegate callbacks below never overlap each other. lock is just for
        // handing state back and forth with the async caller
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
                // cancel before resume() = no delegate callback ever fires, so handle it here
                // or this would just hang forever
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
            record(BackendError.malformedResponse("keine HTTP-Antwort"), preservePartial: false)
            completionHandler(.cancel)
            return
        }

        if http.statusCode == 416 {
            completionHandler(.cancel)
            finish(with: nil)
            return
        }

        guard (200..<300).contains(http.statusCode) else {
            record(BackendError.from(status: http.statusCode, path: pathDescription), preservePartial: http.statusCode < 500)
            completionHandler(.cancel)
            return
        }

        if http.statusCode == 200, startOffset > 0 {
            do {
                try lock.withLock {
                    try handle?.truncate(atOffset: 0)
                    try handle?.seek(toOffset: 0)
                    receivedBytes = 0
                    startOffset = 0
                }
            } catch {
                record(BackendError.transport(error.localizedDescription), preservePartial: false)
                completionHandler(.cancel)
                return
            }
        }

        let expected: Int64
        if http.statusCode == 206, let total = Self.contentRangeTotal(http.value(forHTTPHeaderField: "Content-Range")) {
            expected = total
        } else {
            let length = http.expectedContentLength
            expected = length > 0 ? startOffset + length : length
        }
        lock.withLock { expectedBytes = expected }
        onProgress(receivedBytes, expected)
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
            // probably disk full. cancel() triggers didCompleteWithError, which picks up
            // this recorded error below instead of just reporting "cancelled"
            record(BackendError.transport(error.localizedDescription), preservePartial: true)
            dataTask.cancel()
            return
        }
        if let progress { onProgress(progress.0, progress.1) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(with: error)
    }

    // MARK: - Completion

    private func record(_ error: any Error, preservePartial: Bool) {
        lock.withLock {
            if recordedFailure == nil { recordedFailure = error }
            if !preservePartial { self.preservePartial = false }
        }
    }

    private func finish(with error: (any Error)?) {
        let outcome: (continuation: CheckedContinuation<Void, any Error>?, failure: (any Error)?, keepPartial: Bool, received: Int64)? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true

            let continuation = self.continuation
            self.continuation = nil
            try? handle?.close()
            handle = nil

            return (continuation, recordedFailure, preservePartial, receivedBytes)
        }
        guard let outcome else { return }

        // recorded failure wins if there is one - `error` here would just be the cancellation
        // that a bad status / write error triggered, not the real reason
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
            let keep = outcome.keepPartial && outcome.received > 0 && !(finalError is BackendError && isClientFailure(finalError))
            if !keep {
                try? FileManager.default.removeItem(at: destination)
            }
            outcome.continuation?.resume(throwing: finalError)
        } else {
            outcome.continuation?.resume()
        }
    }

    private func isClientFailure(_ error: any Error) -> Bool {
        guard let backend = error as? BackendError else { return false }
        switch backend {
        case .notFound, .authenticationFailed, .forbidden:
            return true
        default:
            return false
        }
    }

    private static func contentRangeTotal(_ header: String?) -> Int64? {
        guard let header else { return nil }
        // "bytes 100-199/400" or "bytes 100-199/*"
        guard let slash = header.lastIndex(of: "/") else { return nil }
        let total = header[header.index(after: slash)...]
        return Int64(total)
    }
}
