import Foundation

/// Parses a WebDAV `207 Multi-Status` body.
///
/// Two details that are easy to get wrong and are handled explicitly here:
///
/// * A `<response>` may carry several `<propstat>` blocks — typically one `200 OK` holding the
///   properties that exist and one `404 Not Found` listing the ones that do not. Only
///   properties from a 2xx block are kept, otherwise absent properties read as empty values.
/// * Namespaces are processed by `XMLParser`, so elements arrive as `href`, `collection`, …
///   regardless of whether the server writes `D:href`, `d:href` or `ns0:href`.
enum MultiStatusParser {
    struct Entry {
        var href: String
        var isCollection = false
        var contentLength: Int64?
        var lastModified: Date?
        var contentType: String?
        var etag: String?
        /// Status attached to the `<response>` itself rather than to a `<propstat>`. PROPFIND
        /// replies leave this nil; a DELETE that partially failed reports the reason here.
        var responseStatus: Int?
    }

    static func parse(_ data: Data) throws -> [Entry] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate

        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "ungültiges XML"
            throw BackendError.malformedResponse(reason)
        }
        guard !delegate.entries.isEmpty else {
            throw BackendError.malformedResponse("keine <response>-Elemente")
        }
        return delegate.entries
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    var entries: [MultiStatusParser.Entry] = []

    private var currentEntry: MultiStatusParser.Entry?
    /// Properties of the `<propstat>` currently being read, held back until its status is known.
    private var pendingProperties: [String: String] = [:]
    private var pendingIsCollection = false
    private var propstatStatus: String?
    private var responseStatus: String?
    private var insidePropstat = false
    private var text = ""
    private var depthInsideProp = 0

    private let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        // POSIX locale is mandatory: on a German system the default locale parses neither
        // "Fri" nor "Aug", and every timestamp would silently come back nil.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    /// Some servers date-stamp with ISO-8601 instead; used as a fallback.
    private let iso8601 = ISO8601DateFormatter()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        text = ""

        switch elementName {
        case "response":
            currentEntry = MultiStatusParser.Entry(href: "")
            responseStatus = nil
        case "propstat":
            insidePropstat = true
            pendingProperties = [:]
            pendingIsCollection = false
            propstatStatus = nil
        case "prop":
            depthInsideProp += 1
        case "collection":
            if depthInsideProp > 0 { pendingIsCollection = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""

        switch elementName {
        case "href":
            // Only the response's own href counts; hrefs nested elsewhere are ignored.
            if depthInsideProp == 0, currentEntry?.href.isEmpty == true {
                currentEntry?.href = value
            }
        case "status":
            guard depthInsideProp == 0 else { break }
            // Same element name in two roles: inside <propstat> it qualifies the properties,
            // directly inside <response> it is the verdict on the resource itself.
            if insidePropstat { propstatStatus = value } else { responseStatus = value }
        case "prop":
            depthInsideProp = max(0, depthInsideProp - 1)
        case "propstat":
            commitPropstat()
            insidePropstat = false
        case "response":
            if var entry = currentEntry, !entry.href.isEmpty {
                entry.responseStatus = responseStatus.flatMap(Self.statusCode)
                entries.append(entry)
            }
            currentEntry = nil
            responseStatus = nil
        default:
            if depthInsideProp > 0 { pendingProperties[elementName] = value }
        }
    }

    /// Folds a finished `<propstat>` into the entry, but only if the server reported success.
    private func commitPropstat() {
        defer {
            pendingProperties = [:]
            pendingIsCollection = false
            propstatStatus = nil
        }
        guard currentEntry != nil, isSuccess(propstatStatus) else { return }

        if pendingIsCollection { currentEntry?.isCollection = true }
        if let raw = pendingProperties["getcontentlength"], let length = Int64(raw) {
            currentEntry?.contentLength = length
        }
        if let raw = pendingProperties["getlastmodified"] {
            currentEntry?.lastModified = rfc1123.date(from: raw) ?? iso8601.date(from: raw)
        }
        if let raw = pendingProperties["getcontenttype"], !raw.isEmpty {
            // Strip parameters such as "; charset=utf-8" so UTType can match the MIME type.
            currentEntry?.contentType = raw
                .split(separator: ";", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if let raw = pendingProperties["getetag"], !raw.isEmpty {
            currentEntry?.etag = raw
        }
    }

    /// `<status>` looks like `HTTP/1.1 200 OK` — the middle token is the code.
    static func statusCode(_ status: String) -> Int? {
        status.split(separator: " ").compactMap { Int($0) }.first
    }

    /// A missing status is treated as success, since a few servers omit it when every
    /// requested property was found.
    private func isSuccess(_ status: String?) -> Bool {
        guard let status, let code = Self.statusCode(status) else { return true }
        return (200..<300).contains(code)
    }
}
