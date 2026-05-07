import AppKit
import SpriteKit

protocol InteractiveContentViewDelegate: AnyObject {
    func interactiveViewDidClickMascot()
    func interactiveView(_ view: InteractiveContentView, didPressKey keyCode: UInt16, isRepeat: Bool)
    func interactiveView(_ view: InteractiveContentView, didReleaseKey keyCode: UInt16)
}

/// Hosts the SKView and selectively forwards mouse events:
/// only points within the mascot's bounding rect (and only while the
/// scene is `idle` or `controlled`) hit-test to this view; everywhere
/// else, `hitTest` returns nil so clicks pass through to the Dock.
final class InteractiveContentView: NSView {
    weak var delegate: InteractiveContentViewDelegate?
    weak var skView: SKView?
    weak var scene: MascotScene?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let scene = scene, let skView = skView else { return nil }
        switch scene.state {
        case .walking:
            return nil
        case .idle, .controlled:
            let rectInScene = scene.mascotFrameInScene()
            // Scene is anchored at (0,0) and uses resizeFill, so scene
            // coordinates equal SKView coordinates in points.
            let rectInSelf = skView.convert(rectInScene, to: self)
            return rectInSelf.contains(point) ? self : nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.interactiveViewDidClickMascot()
    }

    override func keyDown(with event: NSEvent) {
        delegate?.interactiveView(self, didPressKey: event.keyCode, isRepeat: event.isARepeat)
    }

    override func keyUp(with event: NSEvent) {
        delegate?.interactiveView(self, didReleaseKey: event.keyCode)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Esc is delivered as a key equivalent on some macOS versions.
        if event.keyCode == 53 {
            delegate?.interactiveView(self, didPressKey: 53, isRepeat: false)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
