import Foundation
import Observation

/// One queued or running file transfer, as shown in the transfer panel.
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
    /// `-1` while the server has not told us the total.
    var bytesTotal: Int64 = -1
    var state: State = .waiting

    init(kind: Kind, name: String, boxName: String) {
        self.kind = kind
        self.name = name
        self.boxName = boxName
    }

    /// Nil when the total is unknown, which makes the progress bar indeterminate.
    var fractionCompleted: Double? {
        guard bytesTotal > 0 else { return nil }
        return min(1, Double(bytesDone) / Double(bytesTotal))
    }

    var progressDescription: String {
        switch state {
        case .waiting:
            String(localized: "Wartet")
        case .running where bytesTotal > 0:
            "\(bytesDone.formatted(.byteCount(style: .file))) von \(bytesTotal.formatted(.byteCount(style: .file)))"
        case .running:
            bytesDone.formatted(.byteCount(style: .file))
        case .finished:
            String(localized: "Abgeschlossen")
        case .cancelled:
            String(localized: "Abgebrochen")
        case .failed(let message):
            message
        }
    }
}

/// Rate-limits progress callbacks so a fast transfer does not schedule thousands of hops onto
/// the main actor. Updates pass through on a 200 ms tick or a 1 MB jump, whichever comes first.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReported: Int64 = -1
    private var lastTime = ContinuousClock.now

    private let byteStep: Int64 = 1 << 20
    private let interval = Duration.milliseconds(200)

    /// Returns true when this sample should be forwarded. Completion always passes.
    func shouldReport(done: Int64, total: Int64) -> Bool {
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
