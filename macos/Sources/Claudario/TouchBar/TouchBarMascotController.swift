import AppKit
import SpriteKit

/// Owns the `NSTouchBar` instance + `NSCustomTouchBarItem` that hosts
/// the miniature mascot scene. Wires palette/variant/activity changes
/// pushed from `MascotScene` and forwards Left/Right key state to the
/// scene's move direction. Tapping the touch-bar item is equivalent to
/// pressing Up — the mascot returns to the screen.
final class TouchBarMascotController: NSObject, TouchBarMascotMirror {
    private static let itemId =
        NSTouchBarItem.Identifier("com.claudario.touchbar.mascot")

    private(set) var touchBar: NSTouchBar?
    private var item: NSCustomTouchBarItem?
    private var hostView: TouchBarMascotHostView?
    private var skView: SKView?
    private var scene: TouchBarMascotScene?

    /// Fired when the user taps the Touch Bar mascot — semantically
    /// equivalent to the Up arrow ("return to screen").
    var onReturnToScreen: (() -> Void)?

    func makeTouchBar(colorIndex: Int, variantIndex: Int,
                      activity: MascotActivity) -> NSTouchBar {
        if let tb = touchBar {
            // Re-sync any state that may have changed while we were
            // detached. The cached scene/view keep their x-position
            // across re-entries, which is the desired behavior.
            scene?.setColor(index: colorIndex)
            scene?.setVariant(index: variantIndex)
            scene?.setActivity(activity)
            return tb
        }

        let bar = NSTouchBar()
        bar.defaultItemIdentifiers = [Self.itemId]
        bar.customizationAllowedItemIdentifiers = [Self.itemId]

        let item = NSCustomTouchBarItem(identifier: Self.itemId)
        item.customizationLabel = "Claudario Mascot"
        // Touch Bar item height is ~30pt. We give the strip mascot a
        // wide horizontal canvas; the system clips to available space.
        let frame = NSRect(x: 0, y: 0, width: 685, height: 30)
        let host = TouchBarMascotHostView(frame: frame)
        host.onTap = { [weak self] in self?.onReturnToScreen?() }

        let sk = SKView(frame: frame)
        sk.allowsTransparency = true
        sk.ignoresSiblingOrder = true
        sk.preferredFramesPerSecond = 30
        sk.autoresizingMask = [.width, .height]

        let scene = TouchBarMascotScene(
            size: frame.size,
            colorIndex: colorIndex,
            variantIndex: variantIndex)
        scene.scaleMode = .resizeFill
        scene.setActivity(activity)
        sk.presentScene(scene)

        host.addSubview(sk)
        item.view = host

        bar.templateItems = [item]

        self.touchBar = bar
        self.item = item
        self.hostView = host
        self.skView = sk
        self.scene = scene
        return bar
    }

    func setMoveDirection(_ dir: CGFloat) {
        scene?.moveDirection = dir
    }

    // MARK: - TouchBarMascotMirror

    func touchBarApplyActivity(_ activity: MascotActivity) {
        scene?.setActivity(activity)
    }

    func touchBarApplyColor(index: Int) {
        scene?.setColor(index: index)
    }

    func touchBarApplyVariant(index: Int) {
        scene?.setVariant(index: index)
    }
}

/// Plain NSView whose only job is to translate a tap into the
/// "return to screen" callback. SKView intercepts mouseDown internally,
/// so the tap-capture has to live on the host view above it.
final class TouchBarMascotHostView: NSView {
    var onTap: (() -> Void)?
    override var isFlipped: Bool { false }
    override func mouseDown(with event: NSEvent) {
        onTap?()
    }
}
