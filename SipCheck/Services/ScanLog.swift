import Foundation
import OSLog

/// One recorded scan attempt — enough to triangulate a field note ("this beer at
/// Trader Joe's said Skip It but should've been Try It") after the fact.
///
/// Codable so the whole ring buffer can be persisted and shared as JSON.
struct ScanEvent: Codable {
    let timestamp: Date
    let inputText: String
    let resolvedName: String?
    let style: String?
    let abv: Double?
    let source: String
    let verdict: String
    let score: Double
    let latencyMs: Int
    /// Which entry point produced this scan: "live", "image", or "text".
    let path: String

    // Device context — stamped automatically so notes from different test
    // devices stay legible (e.g. iPhone 14 Pro, which can't run Foundation
    // Models, vs iPhone 15 Pro, which can). Defaulted so call sites are unchanged.
    // `var`, not `let`: immutable properties with initial values are NOT decoded
    // (Swift skips them), which silently re-stamped persisted/synced events with
    // the *current* device's identity on every load.
    /// Hardware id, e.g. "iPhone16,1" (15 Pro) vs "iPhone15,2" (14 Pro).
    var deviceModel: String = DeviceInfo.machineIdentifier
    var osVersion: String = DeviceInfo.osVersion
    var appBuild: String = DeviceInfo.appBuild
    /// Optional preserves decoding of pre-iOS-26 log entries that lack the key.
    var foundationModelsAvailable: Bool? = OnDeviceBeerKnowledge.isAvailable
}

/// Lightweight device/build context for scan telemetry. Foundation only.
enum DeviceInfo {
    /// Hardware identifier string from `uname` (e.g. "iPhone16,1").
    /// Apple-Intelligence capability is derivable from this at triage time.
    static let machineIdentifier: String = {
        var sys = utsname()
        uname(&sys)
        let chars = Mirror(reflecting: sys.machine).children
            .compactMap { $0.value as? Int8 }
            .prefix { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8($0))) }
        return String(chars)
    }()

    static let osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString

    static let appBuild: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }()
}

/// Diagnostic logger for the scan pipeline.
///
/// Three things happen on every `record`:
///   1. a concise one-line summary is emitted via `os.Logger` (subsystem
///      `com.rishishah.sipcheck`, category `scan`) so it shows up in Console /
///      `log stream`,
///   2. the event is appended to an in-memory ring buffer (capped so we never
///      grow unbounded), and
///   3. the buffer is persisted to `Documents/scan_log.json` fire-and-forget on
///      a background queue.
///
/// `exportText()` / `exportJSONURL()` let the log be shared from the app later.
/// Pure Foundation + OSLog — no UI, no network, no macros.
final class ScanLog {

    static let shared = ScanLog()

    /// Max events kept in memory / on disk. Old events are dropped first.
    private static let capacity = 200

    private let logger = Logger(subsystem: "com.rishishah.sipcheck", category: "scan")

    /// Serializes buffer mutation + disk writes off the main thread.
    private let queue = DispatchQueue(label: "com.rishishah.sipcheck.scanlog")

    /// In-memory ring buffer. Only touched on `queue`.
    private var buffer: [ScanEvent] = []

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        self.fileURL = (docs ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("scan_log.json")
        // Warm the buffer from any previously persisted log.
        queue.async { [weak self] in
            self?.loadFromDisk()
        }
    }

    // MARK: - Recording

    /// Emit a one-line summary, append to the ring buffer, and persist — the
    /// persistence step is fire-and-forget on a background queue.
    func record(_ event: ScanEvent) {
        // (a) Concise one-liner for Console / `log stream`.
        logger.log("""
        scan[\(event.path, privacy: .public)] \
        "\(event.resolvedName ?? event.inputText, privacy: .public)" \
        style=\(event.style ?? "-", privacy: .public) \
        abv=\(event.abv ?? -1, privacy: .public) \
        src=\(event.source, privacy: .public) \
        verdict=\(event.verdict, privacy: .public) \
        score=\(event.score, privacy: .public) \
        \(event.latencyMs, privacy: .public)ms \
        dev=\(event.deviceModel, privacy: .public)
        """)

        // (b) + (c) Append to the ring buffer and persist, off the main thread.
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(event)
            if self.buffer.count > Self.capacity {
                self.buffer.removeFirst(self.buffer.count - Self.capacity)
            }
            self.writeToDisk()
        }
    }

    // MARK: - Export

    /// Human-readable dump of the current buffer, newest last. Safe to call from
    /// any thread; snapshots the buffer synchronously.
    func exportText() -> String {
        let snapshot = queue.sync { buffer }
        guard !snapshot.isEmpty else { return "No scan events recorded." }

        let stamp = ISO8601DateFormatter()
        return snapshot.map { e in
            let name = e.resolvedName ?? e.inputText
            let abv = e.abv.map { String(format: "%.1f%%", $0) } ?? "-"
            return "\(stamp.string(from: e.timestamp)) "
                + "[\(e.path)] \"\(name)\" "
                + "style=\(e.style ?? "-") abv=\(abv) "
                + "src=\(e.source) verdict=\(e.verdict) "
                + "score=\(String(format: "%.2f", e.score)) "
                + "\(e.latencyMs)ms "
                + "dev=\(e.deviceModel) os=\(e.osVersion) build=\(e.appBuild) "
                + "foundationModels=\(e.foundationModelsAvailable.map(String.init) ?? "unknown")"
        }.joined(separator: "\n")
    }

    /// URL of the persisted JSON log, or `nil` if nothing has been written yet.
    /// Flushes the current buffer to disk first so the file is up to date.
    func exportJSONURL() -> URL? {
        queue.sync { writeToDisk() }
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    // MARK: - Persistence (call on `queue`)

    private func writeToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(buffer)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("ScanLog: failed to persist scan_log.json — \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ScanEvent].self, from: data) else { return }
        buffer = Array(decoded.suffix(Self.capacity))
    }
}
