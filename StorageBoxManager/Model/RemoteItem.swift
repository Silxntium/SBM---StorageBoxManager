import Foundation
import SwiftUI
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

    var kindDescription: String { // shown in the "Kind" column
        if isDirectory { return String(localized: "Folder") }
        if let description = utType?.localizedDescription { return description }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? String(localized: "Document") : ext.uppercased()
    }

    // KeyPathComparator wants non-optional Comparable, Optional doesn't conform, hence these
    var sortSize: Int64 { size ?? -1 }
    var sortDate: Date { modified ?? .distantPast }

    var enclosingFolder: String {
        path.parent?.displayPath ?? "/"
    }

    var formattedSize: String {
        guard !isDirectory, let size else { return "—" }
        return size.formatted(.byteCount(style: .file))
    }

    var formattedModified: String {
        formattedModified(relative: false)
    }

    func formattedModified(relative: Bool) -> String {
        guard let modified else { return "—" }
        let time = modified.formatted(date: .omitted, time: .shortened)
        if relative {
            let calendar = Calendar.current
            if calendar.isDateInToday(modified) {
                return String(localized: "Today, \(time)")
            }
            if calendar.isDateInYesterday(modified) {
                return String(localized: "Yesterday, \(time)")
            }
            if let weekAgo = calendar.date(byAdding: .day, value: -6, to: Date()),
               modified >= weekAgo {
                let weekday = modified.formatted(.dateTime.weekday(.wide))
                return "\(weekday), \(time)"
            }
        }
        return modified.formatted(date: .abbreviated, time: .shortened)
    }

    var kindCategory: KindCategory {
        if isDirectory { return .folders }
        guard let utType else { return .documents }
        if utType.conforms(to: .image) { return .images }
        if utType.conforms(to: .movie) { return .movies }
        if utType.conforms(to: .audio) { return .audio }
        if utType.conforms(to: .archive) { return .archives }
        return .documents
    }

    func matches(search query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if name.localizedStandardContains(needle) { return true }
        if kindDescription.localizedStandardContains(needle) { return true }
        let ext = (name as NSString).pathExtension
        return !ext.isEmpty && ext.localizedStandardContains(needle)
    }

    func highlightedName(matching query: String) -> AttributedString {
        var attributed = AttributedString(name)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let range = attributed.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return attributed
        }
        attributed[range].backgroundColor = .yellow.opacity(0.35)
        return attributed
    }
}

enum KindCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case folders
    case documents
    case images
    case movies
    case audio
    case archives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .folders: String(localized: "Folders")
        case .documents: String(localized: "Documents")
        case .images: String(localized: "Images")
        case .movies: String(localized: "Movies")
        case .audio: String(localized: "Audio")
        case .archives: String(localized: "Archives")
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .folders: "folder"
        case .documents: "doc"
        case .images: "photo"
        case .movies: "film"
        case .audio: "music.note"
        case .archives: "shippingbox"
        }
    }

    func matches(_ item: RemoteItem) -> Bool {
        switch self {
        case .all: true
        case .folders, .documents, .images, .movies, .audio, .archives:
            item.kindCategory == self
        }
    }
}

enum SortField: String, CaseIterable, Identifiable, Sendable {
    case name
    case modified
    case size
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .modified: String(localized: "Date Modified")
        case .size: String(localized: "Size")
        case .kind: String(localized: "Kind")
        }
    }
}

enum ListingLayout: String, CaseIterable, Identifiable, Sendable {
    case list
    case icons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: String(localized: "as List")
        case .icons: String(localized: "as Icons")
        }
    }

    var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .icons: "square.grid.2x2"
        }
    }
}

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case folder
    case subtree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder: String(localized: "This Folder")
        case .subtree: String(localized: "Subfolders")
        }
    }
}
