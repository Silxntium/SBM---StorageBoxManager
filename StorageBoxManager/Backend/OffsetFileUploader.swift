import Foundation

final class OffsetFileUploader: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let fileURL: URL
    private let offset: Int64
    private let total: Int64
    private let onProgress: @Sendable (Int64, Int64) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var session: URLSession?
    private var isFinished = false

    private init(
        fileURL: URL,
        offset: Int64,
        total: Int64,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) {
        self.fileURL = fileURL
        self.offset = offset
        self.total = total
        self.onProgress = onProgress
    }

    static func upload(
        request: URLRequest,
        fileURL: URL,
        offset: Int64,
        total: Int64,
        configuration: URLSessionConfiguration,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let uploader = OffsetFileUploader(fileURL: fileURL, offset: offset, total: total, onProgress: onProgress)
        try await uploader.run(request: request, configuration: configuration)
    }

    private func run(request: URLRequest, configuration: URLSessionConfiguration) async throws {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        lock.withLock { self.session = session }
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock { self.continuation = continuation }
                session.uploadTask(withStreamedRequest: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStream completionHandler: @escaping (InputStream?) -> Void
    ) {
        completionHandler(Self.makeStream(url: fileURL, offset: offset))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(offset + totalBytesSent, total)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            guard !isFinished else { return nil }
            isFinished = true
            let value = self.continuation
            self.continuation = nil
            return value
        }
        guard let continuation else { return }

        if let error {
            if (error as? URLError)?.code == .cancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                continuation.resume(throwing: BackendError.transport(error.localizedDescription))
            }
            return
        }

        guard let http = task.response as? HTTPURLResponse else {
            continuation.resume(throwing: BackendError.malformedResponse("keine HTTP-Antwort"))
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            continuation.resume(throwing: BackendError.from(status: http.statusCode, path: fileURL.lastPathComponent))
            return
        }
        continuation.resume()
    }

    private static func makeStream(url: URL, offset: Int64) -> InputStream? {
        var input: InputStream?
        var output: OutputStream?
        Stream.getBoundStreams(withBufferSize: 256 * 1024, inputStream: &input, outputStream: &output)
        guard let input, let output else { return nil }

        nonisolated(unsafe) let writer = output
        DispatchQueue.global(qos: .utility).async {
            Self.writeSlice(url: url, offset: offset, to: writer)
        }
        return input
    }

    nonisolated private static func writeSlice(url: URL, offset: Int64, to output: OutputStream) {
        output.open()
        defer { output.close() }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                var written = 0
                chunk.withUnsafeBytes { buffer in
                    guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
                    while written < chunk.count {
                        let n = output.write(base + written, maxLength: chunk.count - written)
                        if n <= 0 { return }
                        written += n
                    }
                }
            }
        } catch {
            return
        }
    }
}
