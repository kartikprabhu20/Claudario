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
    let sound = SoundPlayer()

    var isEnabled: Bool = true {
        didSet { applyEnabled() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(
            at: FSPaths.configDir, withIntermediateDirectories: true)

        overlay = OverlayWindowController(onUserJump: { [weak self] in
            self?.sound.play(.coin)
        })
        overlay.show()

        router = EventRouter(
            onWalk:       { [weak self] in self?.overlay.scene.setState(.walking) },
            onIdle:       { [weak self] in self?.overlay.scene.setState(.idle) },
            onCelebrate:  { [weak self] in
                self?.overlay.scene.celebrate()
                self?.sound.play(.coin)
            },
            onNotify:     { [weak self] in
                self?.overlay.scene.notify()
                self?.sound.play(.notify)
            }
        )

        server = EventServer(router: router)
        server.start(preferredPort: 47821) { port in
            try? "\(port)\n".write(to: FSPaths.portFile, atomically: true, encoding: .utf8)
            NSLog("Claudario: server listening on 127.0.0.1:\(port)")
        }

        statusItem = StatusItemController(appDelegate: self)
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
