import AppKit

enum FSPaths {
    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claudario")
    }
    static var portFile: URL { configDir.appendingPathComponent("port") }
    static var usageFile: URL { configDir.appendingPathComponent("usage.json") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: StatusItemController!
    private(set) var overlay: OverlayWindowController!
    private(set) var server: EventServer!
    private(set) var router: EventRouter!
    private(set) var settings: MascotSettings!
    private(set) var usageMonitor: UsageMonitor!
    private(set) var waterReminder: WaterReminder!
    private(set) var waterNotifier: WaterNotifier!
    let sound = SoundPlayer()

    var isEnabled: Bool = true {
        didSet { applyEnabled() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(
            at: FSPaths.configDir, withIntermediateDirectories: true)

        settings = MascotSettings()

        overlay = OverlayWindowController(
            settings: settings,
            onUserJump: { [weak self] in self?.sound.play(.coin) }
        )
        overlay.scene.attachSettings(settings)
        overlay.show()

        usageMonitor = UsageMonitor(
            fileURL: FSPaths.usageFile,
            onUpdate: { [weak self] usage in
                self?.overlay.scene.setUsage(usage)
            })
        usageMonitor.start()

        router = EventRouter(
            onWalk:       { [weak self] in self?.overlay.scene.setState(.walking) },
            onIdle:       { [weak self] in self?.overlay.scene.setState(.idle) },
            onCelebrate:  { [weak self] in
                self?.overlay.scene.celebrate()
                self?.playRepeated(.coin, count: 3, interval: 1.0)
            },
            onNotify:     { [weak self] in
                self?.overlay.scene.notify()
                self?.playRepeated(.notify, count: 3, interval: 1.0)
            },
            onActivity:   { [weak self] activity in
                self?.overlay.scene.setActivity(activity)
            },
            onHookActivity: { [weak self] in
                self?.usageMonitor.refresh()
            }
        )

        server = EventServer(router: router)
        server.start(preferredPort: 47821) { port in
            try? "\(port)\n".write(to: FSPaths.portFile, atomically: true, encoding: .utf8)
            NSLog("Claudario: server listening on 127.0.0.1:\(port)")
        }

        statusItem = StatusItemController(appDelegate: self, settings: settings)
        settings.onVariantChanged = { [weak self] _ in self?.statusItem.refreshIcon() }
        settings.onColorChanged   = { [weak self] _ in self?.statusItem.refreshIcon() }

        NSApp.applicationIconImage = MascotIconRenderer.renderAppIcon(
            variant: .dog,
            color: MascotPalette.colors[0],
            pointSize: 512)

        overlay.scene.setProgressBarsVisible(settings.showProgressBars)
        settings.onShowProgressBarsChanged = { [weak self] visible in
            self?.overlay.scene.setProgressBarsVisible(visible)
        }

        waterNotifier = WaterNotifier()
        waterNotifier.onAcknowledged = { [weak self] in
            self?.acknowledgeWaterReminder()
        }

        waterReminder = WaterReminder(settings: settings)
        waterReminder.onReminderTick = { [weak self] in
            self?.deliverWaterReminder()
        }
        if settings.waterReminderEnabled {
            // Ask for notification permission lazily on first enable, so
            // users who never turn the reminder on aren't prompted.
            waterNotifier.requestAuthorization()
            waterReminder.start()
        }
        settings.onWaterReminderEnabledChanged = { [weak self] enabled in
            guard let self = self else { return }
            if enabled { self.waterNotifier.requestAuthorization() }
            self.waterReminder.reschedule()
            self.statusItem.rebuildMenu()
        }
        settings.onWaterReminderIntervalChanged = { [weak self] _ in
            self?.waterReminder.reschedule()
            self?.statusItem.rebuildMenu()
        }
        overlay.onWaterReminderAcknowledged = { [weak self] in
            self?.acknowledgeWaterReminder()
        }
    }

    /// Called when the reminder timer fires. Triggers the on-screen
    /// mascot animation, plays the notify chime, and posts a banner.
    private func deliverWaterReminder() {
        overlay.scene.showWaterReminder()
        sound.play(.notify)
        waterNotifier.fire(
            title: "Time for water",
            body: "Take a sip — your dog says hi.")
    }

    /// Called from mascot click or notification-action acknowledgement.
    /// Dismisses the droplet (idempotent) and resets the timer so the
    /// next fire is one full interval from now.
    private func acknowledgeWaterReminder() {
        overlay.scene.dismissWaterReminder()
        waterReminder.acknowledge()
    }

    /// Hook for the "Test: Water Reminder" menu item.
    func fireWaterReminderForTesting() {
        deliverWaterReminder()
    }

    private func playRepeated(_ s: AppSound, count: Int, interval: TimeInterval) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
                self?.sound.play(s)
            }
        }
    }

    private func applyEnabled() {
        if isEnabled {
            overlay.show()
        } else {
            overlay.hide()
            router.reset()
        }
    }
}
