import Foundation
import UniformTypeIdentifiers

struct RemoteItem: Identifiable, Hashable, Sendable {
    var path: RemotePath
    var isDirectory: Bool
    var size: Int64?
    var modified: Date?
    var contentType: String?
    var etag: String?

    var id: RemotePath { path }
    var name: String { path.name }

    var utType: UTType? {
        if isDirectory { return .folder }
        if let contentType, let type = UTType(mimeType: contentType) { return type }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)
    }

    var symbolName: String {
        guard !isDirectory else { return "folder.fill" }
        guard let utType else { return "doc" }
        if utType.conforms(to: .image) { return "photo" }
        if utType.conforms(to: .movie) { return "film" }
        if utType.conforms(to: .audio) { return "music.note" }
        if utType.conforms(to: .archive) { return "shippingbox" }
        if utType.conforms(to: .pdf) { return "doc.richtext" }
        if utType.conforms(to: .sourceCode) || utType.conforms(to: .script) { return "chevron.left.forwardslash.chevron.right" }
        if utType.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    var kindDescription: String { // shown in the "Art" column
        if isDirectory { return String(localized: "Ordner") }
        if let description = utType?.localizedDescription { return description }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? String(localized: "Dokument") : ext.uppercased()
    }

    // KeyPathComparator wants non-optional Comparable, Optional doesn't conform, hence these
    var sortSize: Int64 { size ?? -1 }
    var sortDate: Date { modified ?? .distantPast }

    var formattedSize: String {
        guard !isDirectory, let size else { return "—" }
        return size.formatted(.byteCount(style: .file))
    }

    var formattedModified: String {
        guard let modified else { return "—" }
        return modified.formatted(date: .abbreviated, time: .shortened)
    }
}
