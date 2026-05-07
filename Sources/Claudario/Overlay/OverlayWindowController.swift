import AppKit
import SpriteKit

private enum KeyCode {
    static let left:   UInt16 = 123
    static let right:  UInt16 = 124
    static let up:     UInt16 = 126
    static let esc:    UInt16 = 53

    // Number row → activity slots (matches MascotActivity.allCases order).
    // 1 → idle, 2 → thinking, ... 9 → compacting, 0 → dancing.
    static let n1: UInt16 = 18
    static let n2: UInt16 = 19
    static let n3: UInt16 = 20
    static let n4: UInt16 = 21
    static let n5: UInt16 = 23
    static let n6: UInt16 = 22
    static let n7: UInt16 = 26
    static let n8: UInt16 = 28
    static let n9: UInt16 = 25
    static let n0: UInt16 = 29

    static let comma:  UInt16 = 43   // ','  and  '<'
    static let period: UInt16 = 47   // '.'  and  '>'
    static let c:      UInt16 = 8
    static let v:      UInt16 = 9

    static let activityKeys: [UInt16] = [n1, n2, n3, n4, n5, n6, n7, n8, n9, n0]
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
            initialColorIndex: settings.colorIndex,
            initialVariantIndex: settings.variantIndex
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
            scene.userJump()
            onUserJump()
        case KeyCode.comma:
            scene.setSize(points: settings.nudgeSize(by: -8))
        case KeyCode.period:
            scene.setSize(points: settings.nudgeSize(by: +8))
        case KeyCode.c:
            guard !isRepeat else { return }
            scene.setColor(index: settings.cycleColor())
        case KeyCode.v:
            guard !isRepeat else { return }
            scene.setVariant(index: settings.cycleVariant())
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
