import Foundation
import SwiftUI

/// A configured storage box. The whole point of the app lives here: `displayName` is chosen
/// by the user and has nothing to do with the server hostname the Finder is stuck showing.
struct StorageBox: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var displayName: String
    var host: String
    var username: String
    var tint: BoxTint
    var symbolName: String

    init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        username: String,
        tint: BoxTint = .blue,
        symbolName: String = "externaldrive.fill"
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.username = username
        self.tint = tint
        self.symbolName = symbolName
    }

    /// Base URL for WebDAV requests. Hetzner storage boxes always serve DAV over HTTPS at the root.
    var baseURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/"
        return components.url
    }

    /// Falls back to the hostname so a box is never nameless in the sidebar.
    var resolvedName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? host : trimmed
    }

    static let symbolChoices = [
        "externaldrive.fill", "photo.stack.fill", "film.stack.fill", "music.note.list",
        "doc.on.doc.fill", "archivebox.fill", "shippingbox.fill", "clock.arrow.circlepath",
        "server.rack", "cube.box.fill", "briefcase.fill", "star.fill",
    ]
}

/// A small fixed palette instead of a raw `Color`, so boxes stay `Codable` and legible in
/// both appearances without storing colour components.
enum BoxTint: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }

    var label: String {
        switch self {
        case .blue: String(localized: "Blau")
        case .purple: String(localized: "Violett")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Rot")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Gelb")
        case .green: String(localized: "Grün")
        case .teal: String(localized: "Türkis")
        case .graphite: String(localized: "Grafit")
        }
    }
}
