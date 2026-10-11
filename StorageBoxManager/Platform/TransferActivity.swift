import Foundation

#if canImport(UIKit)
import UIKit
#endif

// Keep user-initiated transfers alive for as long as each platform permits. On macOS an activity
// assertion prevents idle system sleep during uploads without keeping the display awake. iOS
// suspends the app shortly after it leaves the screen, so a background task assertion buys the
// few extra seconds a small transfer needs to finish after the user switches away.
//
// It is not a substitute for a background URLSession: a long upload still stops when the
// assertion expires. It just stops the common case - switching apps for a moment while a
// handful of files go over - from failing.
@MainActor
final class TransferActivity {
    #if canImport(UIKit)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif
    #if os(macOS)
    private var systemActivity: (any NSObjectProtocol)?
    #endif

    func update(isBusy: Bool, hasActiveUploads: Bool) {
        #if canImport(UIKit)
        if isBusy {
            guard identifier == .invalid else { return }
            identifier = UIApplication.shared.beginBackgroundTask(withName: "Transfers") { [weak self] in
                // the system is out of patience - release it or it kills the app outright
                self?.update(isBusy: false, hasActiveUploads: false)
            }
        } else {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
        #endif

        #if os(macOS)
        if hasActiveUploads {
            guard systemActivity == nil else { return }
            systemActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Uploading files"
            )
        } else if let systemActivity {
            ProcessInfo.processInfo.endActivity(systemActivity)
            self.systemActivity = nil
        }
        #endif
    }
}
