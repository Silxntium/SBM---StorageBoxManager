import Foundation

// parses the 207 multistatus XML bodies WebDAV throws at us for PROPFIND/DELETE.
// two gotchas handled here: a <response> can have multiple <propstat> blocks (one 200, one 404
// for props that don't exist - only keep the 200 one), and namespaces are stripped by XMLParser
// so we don't care if the server uses D: or d: or ns0: prefixes
enum MultiStatusParser {
    struct Entry {
        var href: String
        var isCollection = false
        var contentLength: Int64?
        var lastModified: Date?
        var contentType: String?
        var etag: String?
        var responseStatus: Int? // set on partial-failure DELETE responses, nil for normal PROPFIND
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
    private var pendingProperties: [String: String] = [:] // held until we know the propstat succeeded
    private var pendingIsCollection = false
    private var propstatStatus: String?
    private var responseStatus: String?
    private var insidePropstat = false
    private var text = ""
    private var depthInsideProp = 0

    private let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // otherwise "Fri, Aug" fails to parse on non-English systems
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private let iso8601 = ISO8601DateFormatter() // fallback, some servers use this instead

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
            if depthInsideProp == 0, currentEntry?.href.isEmpty == true {
                currentEntry?.href = value
            }
        case "status":
            // "status" means different things depending on where we are - inside propstat vs directly in response
            guard depthInsideProp == 0 else { break }
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
            // drop "; charset=utf-8" etc, just want the mime type
            currentEntry?.contentType = raw
                .split(separator: ";", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if let raw = pendingProperties["getetag"], !raw.isEmpty {
            currentEntry?.etag = raw
        }
    }

    static func statusCode(_ status: String) -> Int? {
        status.split(separator: " ").compactMap { Int($0) }.first // "HTTP/1.1 200 OK" -> 200
    }

    private func isSuccess(_ status: String?) -> Bool {
        guard let status, let code = Self.statusCode(status) else { return true }
        return (200..<300).contains(code)
    }
}
