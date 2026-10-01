import Foundation

#if canImport(UIKit)
import UIKit
#endif

// A Mac keeps running whatever you started. iOS suspends the app shortly after it leaves the
// screen, which would cut a transfer off mid-file. A background task assertion buys the few
// extra seconds a small transfer needs to finish after the user switches away.
//
// It is not a substitute for a background URLSession: a long upload still stops when the
// assertion expires. It just stops the common case - switching apps for a moment while a
// handful of files go over - from failing.
@MainActor
final class TransferActivity {
    #if canImport(UIKit)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    func update(isBusy: Bool) {
        #if canImport(UIKit)
        if isBusy {
            guard identifier == .invalid else { return }
            identifier = UIApplication.shared.beginBackgroundTask(withName: "Transfers") { [weak self] in
                // the system is out of patience - release it or it kills the app outright
                self?.update(isBusy: false)
            }
        } else {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
        #endif
    }
}
