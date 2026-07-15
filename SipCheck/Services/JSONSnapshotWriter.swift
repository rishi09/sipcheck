import Foundation

/// Persists immutable value snapshots on a private serial queue. Multiple
/// mutations that arrive while a write is in flight collapse to the newest
/// snapshot, while the serial queue prevents an older write from winning.
final class JSONSnapshotWriter<Value: Encodable>: @unchecked Sendable {
    private let fileURL: URL
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var pendingSnapshot: Value?
    private var isDrainScheduled = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.queue = DispatchQueue(
            label: "com.rishishah.sipcheck.persistence.\(fileURL.lastPathComponent)",
            qos: .utility
        )
    }

    func schedule(_ snapshot: Value) {
        lock.lock()
        pendingSnapshot = snapshot
        if !isDrainScheduled {
            isDrainScheduled = true
            // Enqueue while holding the lock so flush() cannot overtake this
            // drain between the state change and queue submission.
            queue.async { self.drain() }
        }
        lock.unlock()
    }

    /// Waits for every snapshot scheduled before this call. Used when the app
    /// backgrounds and by persistence round-trip tests.
    func flush() {
        // Synchronize with schedule() before placing the queue fence.
        lock.lock()
        lock.unlock()
        queue.sync {}
    }

    private func drain() {
        while true {
            lock.lock()
            guard let snapshot = pendingSnapshot else {
                isDrainScheduled = false
                lock.unlock()
                return
            }
            pendingSnapshot = nil
            lock.unlock()

            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("Failed to save \(fileURL.lastPathComponent): \(error)")
            }
        }
    }
}
