import Foundation
import Observation

@MainActor
@Observable
final class Transfer: Identifiable {
    enum Kind {
        case upload
        case download

        var symbolName: String {
            switch self {
            case .upload: "arrow.up.circle"
            case .download: "arrow.down.circle"
            }
        }
    }

    enum State: Equatable {
        case waiting
        case running
        case finished
        case cancelled
        case failed(String)

        var isActive: Bool { self == .waiting || self == .running }
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let boxName: String

    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = -1 // -1 = server hasn't told us the total yet
    var state: State = .waiting

    init(kind: Kind, name: String, boxName: String) {
        self.kind = kind
        self.name = name
        self.boxName = boxName
    }

    var fractionCompleted: Double? { // nil -> indeterminate progress bar
        guard bytesTotal > 0 else { return nil }
        return min(1, Double(bytesDone) / Double(bytesTotal))
    }

    var progressDescription: String {
        switch state {
        case .waiting:
            String(localized: "Waiting")
        case .running where bytesTotal > 0:
            "\(bytesDone.formatted(.byteCount(style: .file))) of \(bytesTotal.formatted(.byteCount(style: .file)))"
        case .running:
            bytesDone.formatted(.byteCount(style: .file))
        case .finished:
            String(localized: "Done")
        case .cancelled:
            String(localized: "Cancelled")
        case .failed(let message):
            message
        }
    }
}

// without this a fast transfer spams the main actor with thousands of updates. lets one through
// every 200ms or every 1MB, whichever hits first
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReported: Int64 = -1
    private var lastTime = ContinuousClock.now

    private let byteStep: Int64 = 1 << 20
    private let interval = Duration.milliseconds(200)

    func shouldReport(done: Int64, total: Int64) -> Bool { // completion always gets through
        lock.withLock {
            let now = ContinuousClock.now
            let isComplete = total > 0 && done >= total
            guard !isComplete else { return true }
            guard done - lastReported >= byteStep || now - lastTime >= interval else { return false }
            lastReported = done
            lastTime = now
            return true
        }
    }
}
