import Foundation
import Network

/// Process-wide connectivity signal so callers can skip network work instantly
/// when there is no usable path, instead of waiting out URLSession timeouts.
///
/// The scan flow's contract (CLAUDE.md): the network is never on the critical
/// path. Enrichment calls check `isSatisfied` first — offline means "skip the
/// call entirely", not "spinner until timeout".
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    // Optimistic before the first path update so an early scan never skips
    // enrichment it could have had; a failed call costs one bounded attempt.
    private var satisfied = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.satisfied = (path.status == .satisfied)
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "com.rishishah.sipcheck.netmon"))
    }

    /// `true` when a usable network path exists right now.
    var isSatisfied: Bool {
        lock.lock()
        defer { lock.unlock() }
        return satisfied
    }
}
