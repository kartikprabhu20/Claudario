import AppKit

enum FSPaths {
    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claudario")
    }
    static var portFile: URL { configDir.appendingPathComponent("port") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: StatusItemController!
    private(set) var overlay: OverlayWindowController!
    private(set) var server: EventServer!
    private(set) var router: EventRouter!
    private(set) var settings: MascotSettings!
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
            onUsageUpdate: { [weak self] usage in
                self?.overlay.scene.setUsage(usage)
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
