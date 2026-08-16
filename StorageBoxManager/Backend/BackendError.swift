import Foundation

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
            String(localized: "\"\(host)\" is not a valid address.")
        case .missingPassword:
            String(localized: "No password saved for this box.")
        case .authenticationFailed:
            String(localized: "Login failed.")
        case .forbidden:
            String(localized: "The server refused access.")
        case .notFound(let path):
            String(localized: "\"\(path)\" doesn't exist on the server.")
        case .alreadyExists(let name):
            String(localized: "\"\(name)\" already exists.")
        case .parentMissing(let path):
            String(localized: "The parent folder of \"\(path)\" doesn't exist.")
        case .outOfSpace:
            String(localized: "The box is out of storage space.")
        case .malformedResponse(let detail):
            String(localized: "Unexpected response from the server: \(detail)")
        case .unexpectedStatus(let code):
            String(localized: "The server responded with status \(code).")
        case .transport(let detail):
            String(localized: "Connection error: \(detail)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authenticationFailed:
            String(localized: "Check the username and password in the box settings.")
        case .invalidHost:
            String(localized: "Expected a hostname like \"u123456.your-storagebox.de\".")
        case .missingPassword:
            String(localized: "Edit the box and re-enter the password.")
        case .alreadyExists:
            String(localized: "Choose a different name.")
        case .outOfSpace:
            String(localized: "Free up space on the box, or upgrade its storage.")
        case .forbidden:
            String(localized: "Check whether this sub-account has write access to this path.")
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
