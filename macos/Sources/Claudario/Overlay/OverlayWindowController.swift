import AppKit
import SpriteKit

private enum KeyCode {
    static let left:   UInt16 = 123
    static let right:  UInt16 = 124
    static let up:     UInt16 = 126
    static let down:   UInt16 = 125
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
    static let g:      UInt16 = 5
    static let r:      UInt16 = 15

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
    /// Fired when the user dismisses the water-reminder droplet by
    /// clicking the mascot. Lets the AppDelegate reset the reminder timer.
    var onWaterReminderAcknowledged: (() -> Void)?

    private var leftHeld = false
    private var rightHeld = false
    private var globalMouseMonitor: Any?
    private var touchBarController: TouchBarMascotController?

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
        self.scene.onTick = { [weak self] in self?.updateClickThrough() }
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
            scene.mouseLocationProvider = { [weak self] in
                guard let self = self, self.window.isVisible else { return nil }
                let inWindow = self.window.convertPoint(fromScreen: NSEvent.mouseLocation)
                // Scene uses anchorPoint (0,0) and resizeFill, so SKView
                // points equal scene points.
                return self.skView.convert(inWindow, to: nil)
            }
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
        if scene.state == .playing { scene.exitGame() }
        releaseControl()
        window.ignoresMouseEvents = true
        window.orderOut(nil)
    }

    private func updateClickThrough() {
        guard window.isVisible else { return }
        let shouldCapture: Bool
        switch scene.state {
        case .walking:
            // While walking, the window is normally fully click-through
            // so the rest of the Dock strip stays usable. But if a water
            // reminder is showing, capture clicks on the mascot so the
            // user can dismiss it.
            if scene.waterReminderActive {
                let rectInScene = scene.mascotFrameInScene()
                let rectInWindow = skView.convert(rectInScene, to: nil)
                let rectInScreen = window.convertToScreen(rectInWindow)
                shouldCapture = rectInScreen.contains(NSEvent.mouseLocation)
            } else {
                shouldCapture = false
            }
        case .idle, .controlled:
            let rectInScene = scene.mascotFrameInScene()
            let rectInWindow = skView.convert(rectInScene, to: nil)
            let rectInScreen = window.convertToScreen(rectInWindow)
            shouldCapture = rectInScreen.contains(NSEvent.mouseLocation)
        case .playing:
            shouldCapture = true
        case .touchBar:
            // Mascot lives on the Touch Bar; on-screen overlay is empty.
            shouldCapture = false
        }
        let target = !shouldCapture
        if window.ignoresMouseEvents != target {
            window.ignoresMouseEvents = target
        }
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
        // A click while a water reminder is showing dismisses it,
        // regardless of state. Notify the reminder service so the timer
        // restarts from "now" instead of the previous fire.
        if scene.waterReminderActive {
            scene.dismissWaterReminder()
            onWaterReminderAcknowledged?()
        }
        guard scene.state == .idle else { return }
        enterControlled()
    }

    func interactiveView(_ view: InteractiveContentView, didPressKey keyCode: UInt16, isRepeat: Bool) {
        switch scene.state {
        case .playing:
            handlePlayingKey(keyCode, isRepeat: isRepeat)
            return
        case .touchBar:
            handleTouchBarKey(keyCode, isRepeat: isRepeat)
            return
        case .controlled:
            break
        case .idle, .walking:
            return
        }

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
        case KeyCode.down:
            guard !isRepeat, TouchBarSupport.isAvailable else { return }
            enterTouchBarMode()
        case KeyCode.g:
            guard !isRepeat, scene.currentActivity == .idle else { return }
            scene.setState(.playing)
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

    private func handlePlayingKey(_ keyCode: UInt16, isRepeat: Bool) {
        switch keyCode {
        case KeyCode.up:
            guard !isRepeat else { return }
            scene.tryJump()
            onUserJump()
        case KeyCode.r:
            guard !isRepeat else { return }
            scene.tryRestart()
        case KeyCode.esc:
            scene.exitGame()
        default:
            break
        }
    }

    private func handleTouchBarKey(_ keyCode: UInt16, isRepeat: Bool) {
        switch keyCode {
        case KeyCode.left:
            leftHeld = true
            applyTouchBarMoveDirection()
        case KeyCode.right:
            rightHeld = true
            applyTouchBarMoveDirection()
        case KeyCode.up:
            guard !isRepeat else { return }
            exitTouchBarMode(landingJump: true)
        case KeyCode.esc:
            exitTouchBarMode(landingJump: false)
        default:
            break
        }
    }

    func interactiveView(_ view: InteractiveContentView, didReleaseKey keyCode: UInt16) {
        switch scene.state {
        case .controlled:
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
        case .touchBar:
            switch keyCode {
            case KeyCode.left:
                leftHeld = false
                applyTouchBarMoveDirection()
            case KeyCode.right:
                rightHeld = false
                applyTouchBarMoveDirection()
            default:
                break
            }
        case .idle, .walking, .playing:
            break
        }
    }

    // MARK: - MascotSceneDelegate

    func mascotScene(_ scene: MascotScene, didChangeStateTo state: MascotState) {
        switch state {
        case .controlled, .playing, .touchBar:
            // Keep the window key + keyboard focus so we keep receiving
            // key events (game keys, touch-bar movement keys).
            break
        case .idle, .walking:
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
        switch scene.state {
        case .controlled:
            scene.setState(.idle)
        case .touchBar:
            exitTouchBarMode(landingJump: false)
        default:
            tearDownControl()
        }
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

    private func applyTouchBarMoveDirection() {
        let dir: CGFloat
        switch (leftHeld, rightHeld) {
        case (true, false): dir = -1
        case (false, true): dir = 1
        default:            dir = 0
        }
        touchBarController?.setMoveDirection(dir)
    }

    // MARK: - Touch Bar lifecycle

    func enterTouchBarMode() {
        guard TouchBarSupport.isAvailable else { return }
        guard scene.state == .controlled || scene.state == .idle else { return }
        let controller = ensureTouchBarController()
        scene.touchBarMirror = controller
        // Force AppKit to re-evaluate `makeTouchBar()` so the system
        // picks up our custom bar instead of the default.
        window.touchBar = controller.makeTouchBar(
            colorIndex: settings.colorIndex,
            variantIndex: settings.variantIndex,
            activity: scene.currentActivity)
        leftHeld = false
        rightHeld = false
        scene.setState(.touchBar)
        // Ensure window keeps key focus so we keep receiving key events.
        if !window.isKeyWindow {
            window.allowKeyboardFocus = true
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(contentView)
        }
    }

    private func exitTouchBarMode(landingJump: Bool) {
        guard scene.state == .touchBar else { return }
        touchBarController?.setMoveDirection(0)
        leftHeld = false
        rightHeld = false
        // Detach the custom bar so the system stops rendering it.
        window.touchBar = nil
        // exitTouchBar() sets state to .idle and fires the delegate,
        // which tears down keyboard focus. We re-establish it below if
        // we want a controlled "landing" with a jump.
        scene.exitTouchBar()
        if landingJump {
            enterControlled()
            _ = scene.userJump()
            onUserJump()
        }
    }

    private func ensureTouchBarController() -> TouchBarMascotController {
        if let c = touchBarController { return c }
        let c = TouchBarMascotController()
        c.onReturnToScreen = { [weak self] in
            self?.exitTouchBarMode(landingJump: true)
        }
        touchBarController = c
        return c
    }

    private func installGlobalMouseMonitor() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.scene.state == .playing {
                    self.scene.exitGame()
                } else {
                    self.releaseControl()
                }
            }
        }
    }

    private func removeGlobalMouseMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }
}
