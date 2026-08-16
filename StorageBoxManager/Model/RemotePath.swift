import Foundation

/// A location inside a storage box, held as decoded path *segments* rather than a string.
///
/// Keeping segments apart is what makes correct percent-encoding possible: a file literally
/// named `Urlaub 2024 / Kreta` must encode its slash, which is indistinguishable from a
/// separator once the path has been flattened into a single string. Every URL is therefore
/// built from segments at request time — never by concatenating strings.
struct RemotePath: Hashable, Sendable, Codable {
    /// Decoded segments, no separators, never empty strings.
    private(set) var segments: [String]

    static let root = RemotePath(segments: [])

    init(segments: [String]) {
        self.segments = segments.filter { !$0.isEmpty }
    }

    /// Parses a `<d:href>` from a PROPFIND response, which may be an absolute path
    /// (`/Fotos/Kreta/`) or a full URL (`https://host/Fotos/Kreta/`), always percent-encoded.
    init(href: String) {
        var path = href
        if let components = URLComponents(string: href), components.host != nil {
            path = components.percentEncodedPath
        }
        segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.removingPercentEncoding ?? String($0) }
            .filter { !$0.isEmpty }
    }

    var isRoot: Bool { segments.isEmpty }

    /// Last segment, or an empty string at the root.
    var name: String { segments.last ?? "" }

    var parent: RemotePath? {
        guard !segments.isEmpty else { return nil }
        return RemotePath(segments: segments.dropLast())
    }

    func appending(_ component: String) -> RemotePath {
        RemotePath(segments: segments + [component])
    }

    /// Same location with the final segment replaced — the rename operation.
    func renamed(to newName: String) -> RemotePath {
        guard !segments.isEmpty else { return self }
        return RemotePath(segments: segments.dropLast() + [newName])
    }

    /// Human-readable path for breadcrumbs and error messages. Never used to build requests.
    var displayPath: String {
        segments.isEmpty ? "/" : "/" + segments.joined(separator: "/")
    }

    /// Every ancestor from the root down to and including self — drives the breadcrumb bar.
    var breadcrumbTrail: [RemotePath] {
        (0...segments.count).map { RemotePath(segments: Array(segments.prefix($0))) }
    }

    func isAncestor(of other: RemotePath) -> Bool {
        segments.count < other.segments.count
            && Array(other.segments.prefix(segments.count)) == segments
    }

    // MARK: - URL construction

    /// `urlPathAllowed` permits `/` and `;`, which would let a segment escape its own
    /// position in the path. Both are stripped so a segment can only ever encode to itself.
    private static let segmentAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/;"))

    var encodedPath: String {
        "/" + segments
            .map { $0.addingPercentEncoding(withAllowedCharacters: Self.segmentAllowed) ?? $0 }
            .joined(separator: "/")
    }

    /// Absolute URL against a box's base URL.
    ///
    /// - Parameter isDirectory: appends the trailing slash WebDAV collections require. A
    ///   PROPFIND against a collection without it costs a 301 redirect on Apache.
    func url(relativeTo base: URL, isDirectory: Bool) -> URL? {
        var string = base.absoluteString
        while string.hasSuffix("/") { string.removeLast() }
        string += segments.isEmpty ? "/" : encodedPath
        if isDirectory && !string.hasSuffix("/") { string += "/" }
        return URL(string: string)
    }
}

extension RemotePath: CustomStringConvertible {
    var description: String { displayPath }
}
