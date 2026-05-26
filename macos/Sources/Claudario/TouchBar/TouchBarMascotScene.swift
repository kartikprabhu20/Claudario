import AppKit
import SpriteKit

/// A miniature, faithful re-render of the mascot scaled to the Touch
/// Bar strip. Reuses `MascotVariant.bodyPath` and `MascotPalette` so the
/// silhouette and palette match the on-screen mascot exactly, just
/// smaller. Drives x-position directly each tick from the
/// controller — no auto-walk, no Claude-driven motion.
final class TouchBarMascotScene: SKScene {
    let mascotNode = SKNode()
    private let body = SKShapeNode()
    private let decorationNode = SKNode()
    private let leftEye = SKShapeNode()
    private let rightEye = SKShapeNode()
    private let leftPupil = SKShapeNode()
    private let rightPupil = SKShapeNode()
    private let propLabel = SKLabelNode()

    /// Diameter of the mascot in points. Touch Bar height is ~30pt; we
    /// leave a little headroom so a small prop emoji above the head
    /// doesn't clip.
    private let mascotDiameter: CGFloat = 22

    private var colorIndex: Int = 0
    private var variantIndex: Int = 0
    private var currentActivity: MascotActivity = .idle

    private var variant: MascotVariant {
        MascotVariant.allCases[max(0, min(variantIndex, MascotVariant.allCases.count - 1))]
    }

    /// -1, 0, 1 — set from the controller's key tracking. Multiplied by
    /// `moveSpeed` to advance position each frame.
    var moveDirection: CGFloat = 0
    private let moveSpeed: CGFloat = 280  // points/second

    init(size: CGSize, colorIndex: Int, variantIndex: Int) {
        super.init(size: size)
        self.colorIndex = colorIndex
        self.variantIndex = variantIndex
        anchorPoint = .zero
        backgroundColor = .clear
        addChildNodes()
        rebuildMascot()
        mascotNode.position = CGPoint(x: size.width / 2, y: 2)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didChangeSize(_ oldSize: CGSize) {
        clampX()
    }

    private var lastTickTime: TimeInterval = 0
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastTickTime == 0 {
            dt = 1.0 / 30.0
        } else {
            dt = max(0, min(0.1, currentTime - lastTickTime))
        }
        lastTickTime = currentTime
        if moveDirection != 0 {
            let dx = moveDirection * moveSpeed * CGFloat(dt)
            mascotNode.position.x += dx
            mascotNode.xScale = moveDirection > 0 ? 1 : -1
            clampX()
        }
    }

    private func addChildNodes() {
        body.lineWidth = 1.0
        body.strokeColor = NSColor.black.withAlphaComponent(0.45)
        mascotNode.addChild(body)
        body.addChild(decorationNode)

        for eye in [leftEye, rightEye] {
            eye.fillColor = .white
            eye.strokeColor = NSColor.black.withAlphaComponent(0.6)
            eye.lineWidth = 0.8
            mascotNode.addChild(eye)
        }
        for pupil in [leftPupil, rightPupil] {
            pupil.fillColor = .black
            pupil.strokeColor = .clear
            mascotNode.addChild(pupil)
        }

        propLabel.fontName = "Apple Color Emoji"
        propLabel.verticalAlignmentMode = .center
        propLabel.horizontalAlignmentMode = .center
        propLabel.zPosition = 10
        propLabel.isHidden = true
        mascotNode.addChild(propLabel)

        addChild(mascotNode)
    }

    private func rebuildMascot() {
        let s = mascotDiameter
        let palette = MascotPalette.colors[max(0, min(colorIndex, MascotPalette.colors.count - 1))]
        let v = variant
        let eyeY = v.eyeY(size: s)

        body.path = v.bodyPath(size: s)
        body.fillColor = palette.body

        decorationNode.removeAllChildren()
        v.buildDecorations(into: decorationNode, size: s, palette: palette)

        let eyeR: CGFloat = s * 0.12
        let eyePath = CGPath(
            ellipseIn: CGRect(x: -eyeR, y: -eyeR, width: 2 * eyeR, height: 2 * eyeR),
            transform: nil)
        leftEye.path = eyePath
        rightEye.path = eyePath
        leftEye.position = CGPoint(x: -s * 0.2, y: eyeY)
        rightEye.position = CGPoint(x: s * 0.2, y: eyeY)

        let pupilR: CGFloat = eyeR * 0.55
        let pupilPath = CGPath(
            ellipseIn: CGRect(x: -pupilR, y: -pupilR, width: 2 * pupilR, height: 2 * pupilR),
            transform: nil)
        leftPupil.path = pupilPath
        rightPupil.path = pupilPath
        leftPupil.position = CGPoint(x: -s * 0.2 + pupilR * 0.3, y: eyeY)
        rightPupil.position = CGPoint(x: s * 0.2 + pupilR * 0.3, y: eyeY)

        propLabel.fontSize = s * 0.55
        propLabel.position = CGPoint(x: 0, y: s * 1.05)
        propLabel.text = currentActivity.prop
        propLabel.isHidden = currentActivity.prop.isEmpty
    }

    private func clampX() {
        let margin = mascotDiameter / 2 + 4
        let leftEdge = margin
        let rightEdge = max(margin + 1, size.width - margin)
        mascotNode.position.x = min(max(mascotNode.position.x, leftEdge), rightEdge)
    }

    // MARK: - External setters

    func setActivity(_ activity: MascotActivity) {
        guard currentActivity != activity else { return }
        currentActivity = activity
        propLabel.text = activity.prop
        propLabel.isHidden = activity.prop.isEmpty
    }

    func setColor(index: Int) {
        let count = MascotPalette.colors.count
        guard count > 0 else { return }
        let normalized = ((index % count) + count) % count
        guard normalized != colorIndex else { return }
        colorIndex = normalized
        let palette = MascotPalette.colors[normalized]
        body.fillColor = palette.body
        decorationNode.removeAllChildren()
        variant.buildDecorations(into: decorationNode, size: mascotDiameter, palette: palette)
    }

    func setVariant(index: Int) {
        let count = MascotVariant.allCases.count
        guard count > 0 else { return }
        let normalized = ((index % count) + count) % count
        guard normalized != variantIndex else { return }
        variantIndex = normalized
        rebuildMascot()
    }
}
