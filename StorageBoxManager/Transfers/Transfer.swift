import Foundation
import Observation

@MainActor
@Observable
final class Transfer: Identifiable {
        enum Kind {
        case upload
        case download
        case preview

        var symbolName: String {
            switch self {
            case .upload: "arrow.up.circle"
            case .download: "arrow.down.circle"
            case .preview: "eye"
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
    let boxID: StorageBox.ID?

    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = -1 // -1 = server hasn't told us the total yet
    var state: State = .waiting
    var bytesPerSecond: Double?

    private var rateSamples: [(Date, Int64)] = []

    init(kind: Kind, name: String, boxName: String, boxID: StorageBox.ID? = nil) {
        self.kind = kind
        self.name = name
        self.boxName = boxName
        self.boxID = boxID
    }

    var canRetry: Bool {
        switch state {
        case .failed, .cancelled: true
        case .waiting, .running, .finished: false
        }
    }

    func prepareForRetry() {
        state = .waiting
        bytesPerSecond = nil
        rateSamples.removeAll()
    }

    func recordProgress(done: Int64, total: Int64) {
        bytesDone = done
        if total > 0 { bytesTotal = total }
        guard state == .running else {
            bytesPerSecond = nil
            return
        }

        let now = Date()
        rateSamples.append((now, done))
        let cutoff = now.addingTimeInterval(-5)
        rateSamples.removeAll { $0.0 < cutoff }

        guard let first = rateSamples.first, let last = rateSamples.last else {
            bytesPerSecond = nil
            return
        }
        let elapsed = last.0.timeIntervalSince(first.0)
        let moved = last.1 - first.1
        guard elapsed >= 0.6, moved > 0 else { return }
        bytesPerSecond = Double(moved) / elapsed
    }

    var fractionCompleted: Double? { // nil -> indeterminate progress bar
        guard bytesTotal > 0 else { return nil }
        return min(1, Double(bytesDone) / Double(bytesTotal))
    }

    var rateDescription: String? {
        guard state == .running else { return nil }
        var parts: [String] = []
        if let formattedSpeed { parts.append(formattedSpeed) }
        if let formattedETA { parts.append(formattedETA) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    private var formattedSpeed: String? {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        let megabytes = bytesPerSecond / 1_000_000
        let decimals = megabytes >= 10 ? 1 : 2
        let value = megabytes.formatted(.number.precision(.fractionLength(decimals)))
        return String(localized: "\(value) MB/s")
    }

    private var formattedETA: String? {
        guard let bytesPerSecond, bytesPerSecond > 1, bytesTotal > bytesDone else { return nil }
        let seconds = Double(bytesTotal - bytesDone) / bytesPerSecond
        guard seconds.isFinite, seconds > 0 else { return nil }
        if seconds < 8 {
            return String(localized: "a few seconds left")
        }
        guard let text = Self.etaFormatter.string(from: seconds) else { return nil }
        return String(localized: "\(text) left")
    }

    private static let etaFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
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
            let isFirst = lastReported < 0
            guard isComplete || isFirst || done - lastReported >= byteStep || now - lastTime >= interval else {
                return false
            }
            lastReported = done
            lastTime = now
            return true
        }
    }
}
