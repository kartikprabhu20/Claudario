import AppKit
import SpriteKit

private enum KeyCode {
    static let left:   UInt16 = 123
    static let right:  UInt16 = 124
    static let up:     UInt16 = 126
    static let esc:    UInt16 = 53

    // QWERTY top row → activity slots (matches MascotActivity.allCases order)
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let e: UInt16 = 14
    static let r: UInt16 = 15
    static let t: UInt16 = 17
    static let y: UInt16 = 16
    static let u: UInt16 = 32
    static let i: UInt16 = 34
    static let o: UInt16 = 31
    static let p: UInt16 = 35

    static let comma:  UInt16 = 43   // ','  and  '<'
    static let period: UInt16 = 47   // '.'  and  '>'
    static let c:      UInt16 = 8

    static let activityKeys: [UInt16] = [q, w, e, r, t, y, u, i, o, p]
}

final class OverlayWindowController: NSObject,
                                     InteractiveContentViewDelegate,
                                     MascotSceneDelegate {
    private(set) var window: OverlayWindow!
    let scene: MascotScene
    private var skView: SKView!
    private var contentView: InteractiveContentView!

    private let onUserJump: () -> Void
    private let settings: MascotSettings

    private var leftHeld = false
    private var rightHeld = false
    private var globalMouseMonitor: Any?

    init(settings: MascotSettings, onUserJump: @escaping () -> Void) {
        self.settings = settings
        self.onUserJump = onUserJump
        self.scene = MascotScene(
            initialSize: settings.size,
            initialColorIndex: settings.colorIndex
        )
        super.init()
        self.scene.sceneDelegate = self
        rebuild()
        observeChanges()
    }

    private func rebuild() {
        let info = DockGeometry.current()
        let frame = info.rect

        if window == nil {
            window = OverlayWindow(contentRect: frame)
            contentView = InteractiveContentView(frame: NSRect(origin: .zero, size: frame.size))
            skView = SKView(frame: NSRect(origin: .zero, size: frame.size))
            skView.allowsTransparency = true
            skView.ignoresSiblingOrder = true
            skView.preferredFramesPerSecond = 60
            skView.autoresizingMask = [.width, .height]
            contentView.addSubview(skView)
            contentView.skView = skView
            contentView.scene = scene
            contentView.delegate = self
            window.contentView = contentView
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            scene.size = frame.size
            skView.presentScene(scene)
        } else {
            window.setFrame(frame, display: true)
            contentView.frame = NSRect(origin: .zero, size: frame.size)
            skView.frame = NSRect(origin: .zero, size: frame.size)
            scene.size = frame.size
        }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        releaseControl()
        window.orderOut(nil)
    }

    private func observeChanges() {
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
        nc.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  (note.object as AnyObject?) === self.window else { return }
            self.releaseControl()
        }
        nc.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.releaseControl() }

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

    // MARK: - InteractiveContentViewDelegate

    func interactiveViewDidClickMascot() {
        guard scene.state == .idle else { return }
        enterControlled()
    }

    func interactiveView(_ view: InteractiveContentView, didPressKey keyCode: UInt16, isRepeat: Bool) {
        guard scene.state == .controlled else { return }
        switch keyCode {
        case KeyCode.esc:
            releaseControl()
        case KeyCode.left:
            leftHeld = true
            applyMoveDirection()
        case KeyCode.right:
            rightHeld = true
            applyMoveDirection()
        case KeyCode.up:
            guard !isRepeat else { return }
            if scene.userJump() {
                onUserJump()
            }
        case KeyCode.comma:
            scene.setSize(points: settings.nudgeSize(by: -8))
        case KeyCode.period:
            scene.setSize(points: settings.nudgeSize(by: +8))
        case KeyCode.c:
            guard !isRepeat else { return }
            scene.setColor(index: settings.cycleColor())
        default:
            if let idx = KeyCode.activityKeys.firstIndex(of: keyCode),
               idx < MascotActivity.allCases.count {
                scene.setActivity(MascotActivity.allCases[idx])
            }
        }
    }

    func interactiveView(_ view: InteractiveContentView, didReleaseKey keyCode: UInt16) {
        guard scene.state == .controlled else { return }
        switch keyCode {
        case KeyCode.left:
            leftHeld = false
            applyMoveDirection()
        case KeyCode.right:
            rightHeld = false
            applyMoveDirection()
        default:
            break
        }
    }

    // MARK: - MascotSceneDelegate

    func mascotScene(_ scene: MascotScene, didChangeStateTo state: MascotState) {
        if state != .controlled {
            tearDownControl()
        }
    }

    // MARK: - Control lifecycle

    private func enterControlled() {
        NSApp.activate(ignoringOtherApps: true)
        window.allowKeyboardFocus = true
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        scene.setState(.controlled)
        installGlobalMouseMonitor()
    }

    private func releaseControl() {
        guard scene.state == .controlled else {
            tearDownControl()
            return
        }
        scene.setState(.idle)
    }

    private func tearDownControl() {
        leftHeld = false
        rightHeld = false
        scene.setUserMove(direction: 0)
        window.allowKeyboardFocus = false
        if window.isKeyWindow { window.resignKey() }
        removeGlobalMouseMonitor()
    }

    private func applyMoveDirection() {
        let dir: CGFloat
        switch (leftHeld, rightHeld) {
        case (true, false): dir = -1
        case (false, true): dir = 1
        default:            dir = 0
        }
        scene.setUserMove(direction: dir)
    }

    private func installGlobalMouseMonitor() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            DispatchQueue.main.async { self?.releaseControl() }
        }
    }

    private func removeGlobalMouseMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }
}
