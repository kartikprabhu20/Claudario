import Foundation

/// Fires `onReminderTick` on a configurable cadence. Wraps a
/// `DispatchSourceTimer` so the wake-up cost is negligible. The settings
/// are owned by `MascotSettings`; the service reads them on start /
/// reschedule but does not mutate them.
final class WaterReminder {
    private let settings: MascotSettings
    private let queue = DispatchQueue(label: "claudario.water-reminder")
    private var timer: DispatchSourceTimer?

    /// Fired on the main queue when a reminder is due.
    var onReminderTick: (() -> Void)?

    init(settings: MascotSettings) {
        self.settings = settings
    }

    /// Start (or restart) the timer if `waterReminderEnabled` is true.
    /// Idempotent — calling twice in a row is the same as `reschedule()`.
    func start() {
        stop()
        guard settings.waterReminderEnabled else { return }
        let interval = max(1, settings.waterReminderIntervalMinutes)
        let seconds = DispatchTimeInterval.seconds(interval * 60)
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Fire after one full interval, not immediately on enable —
        // the user just told us they want a reminder in N minutes.
        t.schedule(deadline: .now() + seconds, repeating: seconds)
        t.setEventHandler { [weak self] in self?.fire() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Re-read settings and apply. Used by setting callbacks.
    func reschedule() {
        start()
    }

    /// User signalled "I drank" (clicked mascot or tapped notification
    /// action). Restart the timer from now so the next fire is one full
    /// interval out.
    func acknowledge() {
        guard settings.waterReminderEnabled else { return }
        start()
    }

    private func fire() {
        DispatchQueue.main.async { [weak self] in
            self?.onReminderTick?()
        }
    }
}
