import Foundation

/// Backend failures phrased for the person looking at the window, not for a log file.
enum BackendError: LocalizedError, Equatable {
    case invalidHost(String)
    case missingPassword
    case authenticationFailed
    case forbidden
    case notFound(String)
    case alreadyExists(String)
    case parentMissing(String)
    case outOfSpace
    case malformedResponse(String)
    case unexpectedStatus(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            String(localized: "„\(host)“ ist keine gültige Adresse.")
        case .missingPassword:
            String(localized: "Für diese Box ist kein Passwort hinterlegt.")
        case .authenticationFailed:
            String(localized: "Anmeldung fehlgeschlagen.")
        case .forbidden:
            String(localized: "Der Server hat den Zugriff verweigert.")
        case .notFound(let path):
            String(localized: "„\(path)“ existiert auf dem Server nicht.")
        case .alreadyExists(let name):
            String(localized: "„\(name)“ existiert bereits.")
        case .parentMissing(let path):
            String(localized: "Der übergeordnete Ordner von „\(path)“ existiert nicht.")
        case .outOfSpace:
            String(localized: "Auf der Box ist kein Speicherplatz mehr frei.")
        case .malformedResponse(let detail):
            String(localized: "Unerwartete Antwort vom Server: \(detail)")
        case .unexpectedStatus(let code):
            String(localized: "Der Server hat mit Status \(code) geantwortet.")
        case .transport(let detail):
            String(localized: "Verbindungsfehler: \(detail)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authenticationFailed:
            String(localized: "Benutzername und Passwort in den Box-Einstellungen prüfen.")
        case .invalidHost:
            String(localized: "Erwartet wird ein Hostname wie „u650699.your-storagebox.de“.")
        case .missingPassword:
            String(localized: "Die Box bearbeiten und das Passwort erneut eingeben.")
        case .alreadyExists:
            String(localized: "Einen anderen Namen wählen.")
        case .outOfSpace:
            String(localized: "Auf der Box Platz schaffen oder den Speicher erweitern.")
        case .forbidden:
            String(localized: "Prüfen, ob das Unterkonto Schreibrechte auf diesen Pfad hat.")
        default:
            nil
        }
    }

    /// Maps an HTTP status onto the closest meaningful case.
    static func from(status: Int, path: String) -> BackendError {
        switch status {
        case 401: .authenticationFailed
        case 403: .forbidden
        case 404: .notFound(path)
        case 405, 412: .alreadyExists((path as NSString).lastPathComponent)
        case 409: .parentMissing(path)
        case 507: .outOfSpace
        default: .unexpectedStatus(status)
        }
    }
}
