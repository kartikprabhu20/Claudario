import AppKit
import SpriteKit

final class OverlayWindowController {
    private(set) var window: OverlayWindow!
    let scene: MascotScene
    private var skView: SKView!

    init() {
        scene = MascotScene()
        rebuild()
        observeChanges()
    }

    private func rebuild() {
        let info = DockGeometry.current()
        let frame = info.rect

        if window == nil {
            window = OverlayWindow(contentRect: frame)
            skView = SKView(frame: NSRect(origin: .zero, size: frame.size))
            skView.allowsTransparency = true
            skView.ignoresSiblingOrder = true
            skView.preferredFramesPerSecond = 60
            window.contentView = skView
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            scene.size = frame.size
            skView.presentScene(scene)
        } else {
            window.setFrame(frame, display: true)
            skView.frame = NSRect(origin: .zero, size: frame.size)
            scene.size = frame.size
        }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    private func observeChanges() {
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            forName: NSNotification.Name("com.apple.dock.prefchanged"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
    }
}
