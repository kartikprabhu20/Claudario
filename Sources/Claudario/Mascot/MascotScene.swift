import AppKit
import SpriteKit

final class MascotScene: SKScene {
    private let mascotNode = SKNode()
    private let body = SKShapeNode()
    private let leftEye = SKShapeNode()
    private let rightEye = SKShapeNode()
    private let leftPupil = SKShapeNode()
    private let rightPupil = SKShapeNode()
    private let leftFoot = SKShapeNode()
    private let rightFoot = SKShapeNode()

    private let mascotSize: CGFloat = 44
    private let walkSpeed: CGFloat = 110
    private let walkActionKey = "walk"
    private let footActionKey = "feet"

    private var direction: CGFloat = 1
    private(set) var state: MascotState = .idle

    override init() {
        super.init(size: CGSize(width: 1, height: 1))
        anchorPoint = .zero
        backgroundColor = .clear
        buildMascot()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        positionAtStart()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        positionAtStart()
    }

    private func buildMascot() {
        let s = mascotSize

        let bodyRect = CGRect(x: -s / 2, y: 0, width: s, height: s)
        body.path = CGPath(roundedRect: bodyRect, cornerWidth: s * 0.3, cornerHeight: s * 0.3, transform: nil)
        body.fillColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0)
        body.strokeColor = NSColor.black.withAlphaComponent(0.45)
        body.lineWidth = 1.5
        mascotNode.addChild(body)

        let eyeR: CGFloat = s * 0.12
        let eyeRect = CGRect(x: -eyeR, y: -eyeR, width: 2 * eyeR, height: 2 * eyeR)
        let eyePath = CGPath(ellipseIn: eyeRect, transform: nil)
        configureEye(leftEye, path: eyePath, at: CGPoint(x: -s * 0.2, y: s * 0.7))
        configureEye(rightEye, path: eyePath, at: CGPoint(x: s * 0.2, y: s * 0.7))
        mascotNode.addChild(leftEye)
        mascotNode.addChild(rightEye)

        let pupilR: CGFloat = eyeR * 0.55
        let pupilRect = CGRect(x: -pupilR, y: -pupilR, width: 2 * pupilR, height: 2 * pupilR)
        let pupilPath = CGPath(ellipseIn: pupilRect, transform: nil)
        configurePupil(leftPupil, path: pupilPath, at: CGPoint(x: -s * 0.2 + pupilR * 0.3, y: s * 0.7))
        configurePupil(rightPupil, path: pupilPath, at: CGPoint(x: s * 0.2 + pupilR * 0.3, y: s * 0.7))
        mascotNode.addChild(leftPupil)
        mascotNode.addChild(rightPupil)

        let footW: CGFloat = s * 0.28, footH: CGFloat = s * 0.14
        let footPath = CGPath(
            roundedRect: CGRect(x: -footW / 2, y: -footH, width: footW, height: footH),
            cornerWidth: footH / 2, cornerHeight: footH / 2, transform: nil)
        configureFoot(leftFoot, path: footPath, at: CGPoint(x: -s * 0.2, y: 0))
        configureFoot(rightFoot, path: footPath, at: CGPoint(x: s * 0.2, y: 0))
        mascotNode.addChild(leftFoot)
        mascotNode.addChild(rightFoot)

        addChild(mascotNode)
    }

    private func configureEye(_ node: SKShapeNode, path: CGPath, at point: CGPoint) {
        node.path = path
        node.fillColor = .white
        node.strokeColor = NSColor.black.withAlphaComponent(0.6)
        node.lineWidth = 1
        node.position = point
    }

    private func configurePupil(_ node: SKShapeNode, path: CGPath, at point: CGPoint) {
        node.path = path
        node.fillColor = .black
        node.strokeColor = .clear
        node.position = point
    }

    private func configureFoot(_ node: SKShapeNode, path: CGPath, at point: CGPoint) {
        node.path = path
        node.fillColor = NSColor(calibratedRed: 0.45, green: 0.22, blue: 0.08, alpha: 1.0)
        node.strokeColor = NSColor.black.withAlphaComponent(0.5)
        node.lineWidth = 1
        node.position = point
    }

    private func positionAtStart() {
        guard size.width > mascotSize else { return }
        let y = max(4, (size.height - mascotSize) * 0.25)
        if mascotNode.position == .zero {
            mascotNode.position = CGPoint(x: size.width * 0.1, y: y)
        } else {
            mascotNode.position.y = y
        }
    }

    func setState(_ newState: MascotState) {
        guard newState != state else { return }
        state = newState
        switch state {
        case .idle:
            mascotNode.removeAction(forKey: walkActionKey)
            stopFootAnimation()
        case .walking:
            startWalking()
        }
    }

    private func startWalking() {
        startFootAnimation()
        scheduleNextLeg()
    }

    private func scheduleNextLeg() {
        let margin: CGFloat = mascotSize / 2 + 8
        let leftEdge = margin
        let rightEdge = max(margin + 1, size.width - margin)
        let target = direction > 0 ? rightEdge : leftEdge
        let distance = abs(target - mascotNode.position.x)
        let duration = max(0.2, TimeInterval(distance / walkSpeed))
        mascotNode.xScale = direction > 0 ? 1 : -1
        let move = SKAction.moveTo(x: target, duration: duration)
        let flip = SKAction.run { [weak self] in
            guard let self = self, self.state == .walking else { return }
            self.direction = -self.direction
            self.scheduleNextLeg()
        }
        mascotNode.run(SKAction.sequence([move, flip]), withKey: walkActionKey)
    }

    private func startFootAnimation() {
        let cycle = SKAction.sequence([
            SKAction.run { [weak self] in
                self?.leftFoot.position.y = 4
                self?.rightFoot.position.y = 0
            },
            SKAction.wait(forDuration: 0.18),
            SKAction.run { [weak self] in
                self?.leftFoot.position.y = 0
                self?.rightFoot.position.y = 4
            },
            SKAction.wait(forDuration: 0.18),
        ])
        leftFoot.run(SKAction.repeatForever(cycle), withKey: footActionKey)
    }

    private func stopFootAnimation() {
        leftFoot.removeAction(forKey: footActionKey)
        leftFoot.position.y = 0
        rightFoot.position.y = 0
    }

    func celebrate() {
        let up = SKAction.moveBy(x: 0, y: 36, duration: 0.18)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -36, duration: 0.18)
        down.timingMode = .easeIn
        mascotNode.run(SKAction.sequence([up, down]))
    }

    func notify() {
        let up = SKAction.moveBy(x: 0, y: 14, duration: 0.1)
        let down = SKAction.moveBy(x: 0, y: -14, duration: 0.1)
        mascotNode.run(SKAction.sequence([up, down, up, down]))
    }
}
