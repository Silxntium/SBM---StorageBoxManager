import Foundation

struct StorageQuota: Sendable, Equatable {
    var usedBytes: Int64?
    var availableBytes: Int64?

    var totalBytes: Int64? {
        guard let usedBytes, let availableBytes else { return nil }
        return usedBytes + availableBytes
    }

    var summary: String? {
        if let availableBytes, let totalBytes {
            let free = availableBytes.formatted(.byteCount(style: .file))
            let total = totalBytes.formatted(.byteCount(style: .file))
            return String(localized: "\(free) free of \(total)")
        }
        if let availableBytes {
            let free = availableBytes.formatted(.byteCount(style: .file))
            return String(localized: "\(free) free")
        }
        if let usedBytes {
            let used = usedBytes.formatted(.byteCount(style: .file))
            return String(localized: "\(used) used")
        }
        return nil
    }
}

struct FolderListing: Sendable {
    var items: [RemoteItem]
    var quota: StorageQuota?
}

enum ConflictDecision: Equatable, Sendable {
    case replace
    case keepBoth
    case skip
}

struct ConflictPrompt: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let message: String
}
