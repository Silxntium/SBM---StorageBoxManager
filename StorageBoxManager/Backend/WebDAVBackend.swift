import Foundation
import OSLog

/// WebDAV over HTTPS, which is what a Hetzner storage box serves (Apache `mod_dav`,
/// Basic authentication, realm "WebDAV Restricted").
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

    /// Base URL given directly rather than derived from a box — used to point the backend at
    /// a server other than a Hetzner storage box, which is how it is tested.
    init(baseURL: URL, username: String, password: String) throws {
        guard !password.isEmpty else { throw BackendError.missingPassword }
        self.baseURL = baseURL

        // Set the Authorization header on every request rather than answering an
        // authentication challenge. Reacting to the 401 would double every round-trip, and a
        // sandboxed app has no shared credential storage to fall back on anyway.
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
            throw BackendError.malformedResponse("Pfad „\(path.displayPath)“ ergibt keine gültige URL")
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

    /// Requests exactly the properties the file list shows. Asking for `<allprop>` instead
    /// would make Apache emit a much larger body for no extra information.
    private static let propfindBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <propfind xmlns="DAV:">
          <prop>
            <resourcetype/>
            <getcontentlength/>
            <getlastmodified/>
            <getcontenttype/>
            <getetag/>
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
        // Depth 0 asks only about the root itself, so the reply stays tiny even on a full box.
        let request = try propfindRequest(path: .root, depth: "0")
        try await send(request, path: .root, accepting: [207, 200])
    }

    func list(_ path: RemotePath) async throws -> [RemoteItem] {
        // Depth 1 rather than infinity: Apache rejects infinite-depth PROPFIND by default
        // (DavDepthInfinity off), so the tree is walked one level at a time.
        let request = try propfindRequest(path: path, depth: "1")
        let data = try await send(request, path: path, accepting: [207, 200])

        return try MultiStatusParser.parse(data)
            .map { entry -> RemoteItem in
                let itemPath = RemotePath(href: entry.href)
                return RemoteItem(
                    path: itemPath,
                    isDirectory: entry.isCollection,
                    size: entry.contentLength,
                    modified: entry.lastModified,
                    contentType: entry.contentType,
                    etag: entry.etag
                )
            }
            // A Depth-1 PROPFIND always includes the collection itself as the first response.
            // Without this the folder would appear to contain itself, and recursion would follow.
            .filter { $0.path != path }
    }

    func createDirectory(at path: RemotePath) async throws {
        let request = try makeRequest("MKCOL", path: path, isDirectory: true)
        try await send(request, path: path, accepting: [201])
    }

    func move(from source: RemotePath, to destination: RemotePath, isDirectory: Bool) async throws {
        guard let destinationURL = destination.url(relativeTo: baseURL, isDirectory: isDirectory) else {
            throw BackendError.malformedResponse("Zielpfad ergibt keine gültige URL")
        }
        var request = try makeRequest("MOVE", path: source, isDirectory: isDirectory)
        // Destination must be an absolute URL, encoded exactly like the request line — which
        // is why it comes out of the same RemotePath encoder rather than string interpolation.
        request.setValue(destinationURL.absoluteString, forHTTPHeaderField: "Destination")
        // Overwrite: F turns "a file of that name is already there" into a 412 instead of
        // silently destroying it.
        request.setValue("F", forHTTPHeaderField: "Overwrite")

        do {
            try await send(request, path: source, accepting: [201, 204])
        } catch BackendError.alreadyExists {
            throw BackendError.alreadyExists(destination.name)
        }
    }

    func delete(_ path: RemotePath, isDirectory: Bool) async throws {
        let request = try makeRequest("DELETE", path: path, isDirectory: isDirectory)
        // mod_dav removes collections recursively and answers 207 when only part of the tree
        // could be deleted; that body is inspected below.
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
        var request = try makeRequest("PUT", path: path, isDirectory: false)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let data: Data
        let response: URLResponse
        do {
            // Uploading from a file keeps the body off the heap, so a 20 GB archive costs no
            // more memory than a 20 KB one.
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

    // MARK: - Helpers

    /// Finds the first failing resource in a Multi-Status body, so that a DELETE which only
    /// removed part of a tree surfaces as an error instead of a silent success.
    private static func firstFailure(inMultiStatus data: Data) -> (path: String, status: Int)? {
        guard !data.isEmpty, let entries = try? MultiStatusParser.parse(data) else { return nil }
        for entry in entries {
            guard let status = entry.responseStatus, !(200..<300).contains(status) else { continue }
            return (RemotePath(href: entry.href).displayPath, status)
        }
        return nil
    }
}

/// Reports PUT progress. Holds nothing but an immutable closure, so it is safe to hand to
/// URLSession's delegate queue.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
}
