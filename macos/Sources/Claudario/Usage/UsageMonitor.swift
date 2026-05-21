import Foundation

/// Reads `~/.claudario/usage.json` — written by the user's statusline command —
/// to surface the same `context_window.used_percentage` and
/// `rate_limits.five_hour.used_percentage` that Claude Code shows in the
/// statusline. Polled on a 60s timer and refreshed on every hook event so the
/// bars update both passively and reactively.
final class UsageMonitor {
    private let fileURL: URL
    private let onUpdate: (SessionUsage) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "claudario.usage-monitor")

    init(fileURL: URL, onUpdate: @escaping (SessionUsage) -> Void) {
        self.fileURL = fileURL
        self.onUpdate = onUpdate
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .seconds(60))
        t.setEventHandler { [weak self] in self?.readAndEmit() }
        t.resume()
        timer = t
    }

    /// Trigger an immediate refresh outside the 60s cadence — e.g. when a
    /// hook event arrives so the bar updates as soon as the statusline has
    /// likely just rewritten the sidecar.
    func refresh() {
        queue.async { [weak self] in self?.readAndEmit() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func readAndEmit() {
        let usage = readSnapshot()
        DispatchQueue.main.async { self.onUpdate(usage) }
    }

    private func readSnapshot() -> SessionUsage {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .zero
        }
        let ctx = (obj["context_window"] as? [String: Any])?["used_percentage"]
        let five = ((obj["rate_limits"] as? [String: Any])?["five_hour"] as? [String: Any])?["used_percentage"]
        let context = (ctx as? NSNumber)?.doubleValue ?? 0
        let session = (five as? NSNumber)?.doubleValue ?? 0
        return SessionUsage(
            sessionPercent: min(1.0, max(0.0, session / 100.0)),
            contextPercent: min(1.0, max(0.0, context / 100.0)))
    }
}
