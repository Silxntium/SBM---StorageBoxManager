import Foundation
import OSLog

// talks WebDAV over HTTPS - Apache mod_dav on the storage box side, Basic auth
struct WebDAVBackend: StorageBackend {
    let baseURL: URL

    private let authorization: String
    private let session: URLSession
    private let configuration: URLSessionConfiguration
    private static let logger = Logger(subsystem: "de.silxnt.StorageBoxManager", category: "WebDAV")

    init(box: StorageBox, password: String) throws {
        guard let baseURL = box.baseURL, baseURL.host() != nil else {
            throw BackendError.invalidHost(box.host)
        }
        try self.init(baseURL: baseURL, username: box.username, password: password)
    }

    // separate init so tests can point this at a local Apache instead of a real box
    init(baseURL: URL, username: String, password: String) throws {
        guard !password.isEmpty else { throw BackendError.missingPassword }
        self.baseURL = baseURL

        // just set the header ourselves instead of dealing with URLSession's auth challenge
        // dance - avoids a wasted 401 roundtrip on literally every request
        let credentials = "\(username):\(password)"
        authorization = "Basic " + Data(credentials.utf8).base64EncodedString()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpAdditionalHeaders = ["Authorization": authorization]
        self.configuration = configuration
        session = URLSession(configuration: configuration)
    }

    // MARK: - Requests

    private func makeRequest(
        _ method: String,
        path: RemotePath,
        isDirectory: Bool
    ) throws -> URLRequest {
        guard let url = path.url(relativeTo: baseURL, isDirectory: isDirectory) else {
            throw BackendError.malformedResponse("path \"\(path.displayPath)\" doesn't form a valid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    @discardableResult
    private func send(
        _ request: URLRequest,
        path: RemotePath,
        accepting accepted: Set<Int>
    ) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw BackendError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.malformedResponse("keine HTTP-Antwort")
        }
        guard accepted.contains(http.statusCode) else {
            Self.logger.error(
                "\(request.httpMethod ?? "?", privacy: .public) \(path.displayPath, privacy: .private) → \(http.statusCode, privacy: .public)"
            )
            throw BackendError.from(status: http.statusCode, path: path.displayPath)
        }
        return data
    }

    // only ask for what the table actually shows, allprop is way more data than we need
    private static let propfindBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <propfind xmlns="DAV:">
          <prop>
            <resourcetype/>
            <getcontentlength/>
            <getlastmodified/>
            <getcontenttype/>
            <getetag/>
            <quota-available-bytes/>
            <quota-used-bytes/>
          </prop>
        </propfind>
        """.utf8)

    private func propfindRequest(path: RemotePath, depth: String) throws -> URLRequest {
        var request = try makeRequest("PROPFIND", path: path, isDirectory: true)
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.propfindBody
        return request
    }

    // MARK: - StorageBackend

    func probe() async throws {
        let request = try propfindRequest(path: .root, depth: "0") // depth 0 = just check root exists, keep it cheap
        try await send(request, path: .root, accepting: [207, 200])
    }

    func inspect(_ path: RemotePath) async throws -> FolderListing {
        // NOTE: depth infinity gets rejected by Apache (DavDepthInfinity off by default), so we
        // walk one level at a time instead. cost us an hour to figure out the first time.
        let request = try propfindRequest(path: path, depth: "1")
        let data = try await send(request, path: path, accepting: [207, 200])
        let entries = try MultiStatusParser.parse(data)

        var quota: StorageQuota?
        var items: [RemoteItem] = []
        for entry in entries {
            let itemPath = RemotePath(href: entry.href)
            if itemPath == path {
                if entry.quotaUsed != nil || entry.quotaAvailable != nil {
                    quota = StorageQuota(usedBytes: entry.quotaUsed, availableBytes: entry.quotaAvailable)
                }
                continue
            }
            items.append(
                RemoteItem(
                    path: itemPath,
                    isDirectory: entry.isCollection,
                    size: entry.contentLength,
                    modified: entry.lastModified,
                    contentType: entry.contentType,
                    etag: entry.etag
                )
            )
        }
        return FolderListing(items: items, quota: quota)
    }

    func resourceSize(at path: RemotePath) async throws -> Int64? {
        let request = try makeRequest("HEAD", path: path, isDirectory: false)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BackendError.malformedResponse("keine HTTP-Antwort")
            }
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 405 { return try await propfindSize(at: path) }
                throw BackendError.from(status: http.statusCode, path: path.displayPath)
            }
            if http.expectedContentLength > 0 { return http.expectedContentLength }
            if let raw = http.value(forHTTPHeaderField: "Content-Length"), let length = Int64(raw) {
                return length
            }
            return try await propfindSize(at: path)
        } catch let error as BackendError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return try await propfindSize(at: path)
        }
    }

    private func propfindSize(at path: RemotePath) async throws -> Int64? {
        do {
            var request = try makeRequest("PROPFIND", path: path, isDirectory: false)
            request.setValue("0", forHTTPHeaderField: "Depth")
            request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.propfindBody
            let data = try await send(request, path: path, accepting: [207, 200])
            return try MultiStatusParser.parse(data).first?.contentLength
        } catch let error as BackendError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    func createDirectory(at path: RemotePath) async throws {
        let request = try makeRequest("MKCOL", path: path, isDirectory: true)
        try await send(request, path: path, accepting: [201])
    }

    func move(from source: RemotePath, to destination: RemotePath, isDirectory: Bool) async throws {
        guard let destinationURL = destination.url(relativeTo: baseURL, isDirectory: isDirectory) else {
            throw BackendError.malformedResponse("destination path doesn't form a valid URL")
        }
        var request = try makeRequest("MOVE", path: source, isDirectory: isDirectory)
        request.setValue(destinationURL.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue("F", forHTTPHeaderField: "Overwrite") // "F" = don't clobber an existing file, fail instead

        do {
            try await send(request, path: source, accepting: [201, 204])
        } catch BackendError.alreadyExists {
            throw BackendError.alreadyExists(destination.name)
        }
    }

    func copy(from source: RemotePath, to destination: RemotePath, isDirectory: Bool) async throws {
        guard let destinationURL = destination.url(relativeTo: baseURL, isDirectory: isDirectory) else {
            throw BackendError.malformedResponse("destination path doesn't form a valid URL")
        }
        var request = try makeRequest("COPY", path: source, isDirectory: isDirectory)
        request.setValue(destinationURL.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue("F", forHTTPHeaderField: "Overwrite")
        if isDirectory {
            request.setValue("infinity", forHTTPHeaderField: "Depth")
        }

        do {
            try await send(request, path: source, accepting: [201, 204])
        } catch BackendError.alreadyExists {
            throw BackendError.alreadyExists(destination.name)
        }
    }

    func delete(_ path: RemotePath, isDirectory: Bool) async throws {
        let request = try makeRequest("DELETE", path: path, isDirectory: isDirectory)
        // 207 = partial delete, some files in the folder couldn't be removed - check the body
        let data = try await send(request, path: path, accepting: [200, 202, 204, 207])
        if let failure = Self.firstFailure(inMultiStatus: data) {
            throw BackendError.from(status: failure.status, path: failure.path)
        }
    }

    func download(
        _ path: RemotePath,
        to localURL: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let request = try makeRequest("GET", path: path, isDirectory: false)
        let downloader = StreamingDownloader(
            destination: localURL,
            pathDescription: path.displayPath,
            onProgress: onProgress
        )
        try await downloader.run(request: request, configuration: configuration)
    }

    func upload(
        _ localURL: URL,
        to path: RemotePath,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let localSize = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if localSize > 0 { onProgress(0, localSize) }

        let remoteSize = try await resourceSize(at: path)
        if let remoteSize, remoteSize == localSize, localSize > 0 {
            onProgress(localSize, localSize)
            return
        }

        if let remoteSize, remoteSize > 0, remoteSize < localSize {
            do {
                try await uploadSlice(
                    localURL,
                    to: path,
                    offset: remoteSize,
                    total: localSize,
                    onProgress: onProgress
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.logger.info("ranged upload not accepted, sending the whole file")
            }
        }

        try await uploadFull(localURL, to: path, onProgress: onProgress)
    }

    private func uploadFull(
        _ localURL: URL,
        to path: RemotePath,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        var request = try makeRequest("PUT", path: path, isDirectory: false)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(offset: 0, total: nil, onProgress: onProgress)
        let data: Data
        let response: URLResponse
        do {
            // fromFile: streams instead of loading the whole thing into memory first
            (data, response) = try await session.upload(for: request, fromFile: localURL, delegate: delegate)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw BackendError.transport(error.localizedDescription)
        }
        _ = data

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.malformedResponse("keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.from(status: http.statusCode, path: path.displayPath)
        }
    }

    private func uploadSlice(
        _ localURL: URL,
        to path: RemotePath,
        offset: Int64,
        total: Int64,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        var request = try makeRequest("PUT", path: path, isDirectory: false)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("bytes \(offset)-\(total - 1)/\(total)", forHTTPHeaderField: "Content-Range")
        request.setValue(String(total - offset), forHTTPHeaderField: "Content-Length")
        try await OffsetFileUploader.upload(
            request: request,
            fileURL: localURL,
            offset: offset,
            total: total,
            configuration: configuration,
            onProgress: onProgress
        )
    }

    // MARK: - Helpers

    private static func firstFailure(inMultiStatus data: Data) -> (path: String, status: Int)? {
        guard !data.isEmpty, let entries = try? MultiStatusParser.parse(data) else { return nil }
        for entry in entries {
            guard let status = entry.responseStatus, !(200..<300).contains(status) else { continue }
            return (RemotePath(href: entry.href).displayPath, status)
        }
        return nil
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let offset: Int64
    private let total: Int64?
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(offset: Int64, total: Int64?, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.offset = offset
        self.total = total
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let expected = total ?? (offset + totalBytesExpectedToSend)
        onProgress(offset + totalBytesSent, expected)
    }
}
