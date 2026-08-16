import Foundation

// path as segments instead of a string - keeps encoding sane. a file named "a / b" needs its
// slash escaped, which you can't tell apart from a real path separator once it's all one string
struct RemotePath: Hashable, Sendable, Codable {
    private(set) var segments: [String]

    static let root = RemotePath(segments: [])

    init(segments: [String]) {
        self.segments = segments.filter { !$0.isEmpty }
    }

    // href can be either "/Fotos/Kreta/" or "https://host/Fotos/Kreta/" depending on the server
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
    var name: String { segments.last ?? "" }

    var parent: RemotePath? {
        guard !segments.isEmpty else { return nil }
        return RemotePath(segments: segments.dropLast())
    }

    func appending(_ component: String) -> RemotePath {
        RemotePath(segments: segments + [component])
    }

    func renamed(to newName: String) -> RemotePath {
        guard !segments.isEmpty else { return self }
        return RemotePath(segments: segments.dropLast() + [newName])
    }

    // for UI display only (breadcrumbs, errors) - never feed this into a request
    var displayPath: String {
        segments.isEmpty ? "/" : "/" + segments.joined(separator: "/")
    }

    var breadcrumbTrail: [RemotePath] {
        (0...segments.count).map { RemotePath(segments: Array(segments.prefix($0))) }
    }

    func isAncestor(of other: RemotePath) -> Bool {
        segments.count < other.segments.count
            && Array(other.segments.prefix(segments.count)) == segments
    }

    // MARK: - URL construction

    // urlPathAllowed still lets / and ; through, which would let a segment break out of its
    // slot - strip those too so a segment can only ever turn into itself
    private static let segmentAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/;"))

    var encodedPath: String {
        "/" + segments
            .map { $0.addingPercentEncoding(withAllowedCharacters: Self.segmentAllowed) ?? $0 }
            .joined(separator: "/")
    }

    func url(relativeTo base: URL, isDirectory: Bool) -> URL? {
        var string = base.absoluteString
        while string.hasSuffix("/") { string.removeLast() }
        string += segments.isEmpty ? "/" : encodedPath
        // trailing slash matters - PROPFIND on a collection without it gets a 301 from Apache
        if isDirectory && !string.hasSuffix("/") { string += "/" }
        return URL(string: string)
    }
}

extension RemotePath: CustomStringConvertible {
    var description: String { displayPath }
}
