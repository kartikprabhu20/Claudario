import AppKit
import SpriteKit

protocol MascotSceneDelegate: AnyObject {
    func mascotScene(_ scene: MascotScene, didChangeStateTo state: MascotState)
}

final class MascotScene: SKScene {
    weak var sceneDelegate: MascotSceneDelegate?
    var onTick: (() -> Void)?
    /// Set by the controller; returns the cursor's position in scene
    /// coordinates each frame, or nil when the cursor is unavailable
    /// (e.g. window hidden). Drives the petting gesture detector.
    var mouseLocationProvider: (() -> CGPoint?)?

    let mascotNode = SKNode()
    private let body = SKShapeNode()
    private let decorationNode = SKNode()
    private let leftEye = SKShapeNode()
    private let rightEye = SKShapeNode()
    private let leftPupil = SKShapeNode()
    private let rightPupil = SKShapeNode()
    private let leftFoot = SKShapeNode()
    private let rightFoot = SKShapeNode()
    private let propLabel = SKLabelNode()

    private(set) var mascotSize: CGFloat = 44
    private var colorIndex: Int = 0
    private var variantIndex: Int = 0
    private(set) var currentActivity: MascotActivity = .idle

    private var game: DinoGameController?
    private weak var settingsRef: MascotSettings?
    /// Latest Claude state event that arrived while the player was in
    /// the dino game. Replayed on game exit so the mascot reflects
    /// whatever Claude was doing once the user returns from playing.
    private var pendingState: MascotState?
    private var pendingActivity: MascotActivity?

    private var variant: MascotVariant {
        MascotVariant.allCases[max(0, min(variantIndex, MascotVariant.allCases.count - 1))]
    }

    private let baseWalkSpeed: CGFloat = 110
    private var walkSpeed: CGFloat { baseWalkSpeed * currentActivity.speedMultiplier.nonZeroOr(1) }

    private let walkActionKey = "walk"
    private let userMoveActionKey = "userMove"
    private let footActionKey = "feet"
    private let jumpActionKey = "jump"
    private let decorationActionKey = "decoration"
    private let bodySquashKey = "bodySquash"
    private let eyeActionKey = "eye"
    private let pupilActionKey = "pupil"

    private var direction: CGFloat = 1
    private var userMoveDirection: CGFloat = 0
    private(set) var state: MascotState = .idle

    // Petting state: a continuous level (0...1) that builds when the
    // cursor wags back-and-forth over the head and decays when it stops.
    // Drives squint/sway/tail-wag visuals directly each frame.
    private var pettingLevel: CGFloat = 0
    private var prevPettingLevel: CGFloat = 0
    private var lastMouseSceneX: CGFloat?
    private var lastDirection: Int = 0
    private var reversalTimes: [TimeInterval] = []
    private var lastTickTime: TimeInterval = 0
    private var walkPaused: Bool = false

    init(initialSize: Int, initialColorIndex: Int, initialVariantIndex: Int) {
        super.init(size: CGSize(width: 1, height: 1))
        self.mascotSize = CGFloat(initialSize)
        self.colorIndex = initialColorIndex
        self.variantIndex = initialVariantIndex
        anchorPoint = .zero
        backgroundColor = .clear
        addChildNodes()
        rebuildMascot()
    }

    convenience override init() {
        self.init(initialSize: MascotSettings.defaultSize,
                  initialColorIndex: MascotSettings.defaultColorIndex,
                  initialVariantIndex: MascotSettings.defaultVariantIndex)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        positionAtStart()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        positionAtStart()
        clampCurrentX()
    }

    override func update(_ currentTime: TimeInterval) {
        onTick?()
        if state == .playing {
            game?.tick(currentTime)
        }
        tickPetting(currentTime: currentTime)
    }

    private func addChildNodes() {
        body.lineWidth = 1.5
        body.strokeColor = NSColor.black.withAlphaComponent(0.45)
        mascotNode.addChild(body)
        // Parented under body so decorations (inner ears, whiskers, etc.)
        // inherit body's squash/rotate animations.
        body.addChild(decorationNode)

        for eye in [leftEye, rightEye] {
            eye.fillColor = .white
            eye.strokeColor = NSColor.black.withAlphaComponent(0.6)
            eye.lineWidth = 1
            mascotNode.addChild(eye)
        }
        for pupil in [leftPupil, rightPupil] {
            pupil.fillColor = .black
            pupil.strokeColor = .clear
            mascotNode.addChild(pupil)
        }
        for foot in [leftFoot, rightFoot] {
            foot.strokeColor = NSColor.black.withAlphaComponent(0.5)
            foot.lineWidth = 1
            mascotNode.addChild(foot)
        }

        // SKLabelNode falls back to Helvetica by default, which has no
        // emoji glyphs — the activity props would render as missing
        // characters. Apple Color Emoji handles every prop in our table.
        propLabel.fontName = "Apple Color Emoji"
        propLabel.verticalAlignmentMode = .center
        propLabel.horizontalAlignmentMode = .center
        propLabel.zPosition = 10
        propLabel.isHidden = true
        mascotNode.addChild(propLabel)

        addChild(mascotNode)
    }

    private func rebuildMascot() {
        let s = mascotSize
        let palette = MascotPalette.colors[max(0, min(colorIndex, MascotPalette.colors.count - 1))]
        let v = variant
        let eyeY = v.eyeY(size: s)
        let footY = v.footY(size: s)

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

        let footW: CGFloat = s * 0.28, footH: CGFloat = s * 0.14
        let footPath = CGPath(
            roundedRect: CGRect(x: -footW / 2, y: -footH, width: footW, height: footH),
            cornerWidth: footH / 2, cornerHeight: footH / 2, transform: nil)
        leftFoot.path = footPath
        rightFoot.path = footPath
        leftFoot.fillColor = palette.foot
        rightFoot.fillColor = palette.foot
        leftFoot.position = CGPoint(x: -s * 0.2, y: footY)
        rightFoot.position = CGPoint(x: s * 0.2, y: footY)

        propLabel.fontSize = s * 0.5
        propLabel.position = CGPoint(x: 0, y: s * 1.15)

        positionAtStart()
        clampCurrentX()
    }

    /// y-coordinate where the mascot's feet rest. We keep it low so the
    /// extra headroom (`DockGeometry.heightMultiplier`) above the Dock is
    /// available for jumps and props.
    var groundY: CGFloat { 4 }

    func attachSettings(_ settings: MascotSettings) {
        self.settingsRef = settings
    }

    func currentColor() -> MascotColor {
        let count = MascotPalette.colors.count
        let i = max(0, min(colorIndex, count - 1))
        return MascotPalette.colors[i]
    }

    private func positionAtStart() {
        guard size.width > mascotSize else { return }
        let y = groundY
        if mascotNode.position == .zero {
            mascotNode.position = CGPoint(x: size.width * 0.1, y: y)
        } else {
            mascotNode.position.y = y
        }
    }

    // MARK: - State

    func setState(_ newState: MascotState) {
        // While playing, Claude-driven state changes (`onWalk`, `onIdle`)
        // are deferred and replayed once the player exits the game via
        // `exitGame()` — that path bypasses this guard.
        if state == .playing && newState != .playing {
            pendingState = newState
            return
        }
        guard newState != state else { return }
        state = newState
        switch state {
        case .idle:
            clearAutoMotion()
            userMoveDirection = 0
        case .walking:
            mascotNode.removeAction(forKey: userMoveActionKey)
            userMoveDirection = 0
            startAutoMotionForActivity()
        case .controlled:
            clearAutoMotion()
        case .playing:
            startGame()
        }
        sceneDelegate?.mascotScene(self, didChangeStateTo: state)
    }

    private func startGame() {
        guard let settings = settingsRef else { return }
        clearAutoMotion()
        mascotNode.removeAction(forKey: userMoveActionKey)
        mascotNode.removeAction(forKey: jumpActionKey)
        mascotNode.removeAction(forKey: decorationActionKey)
        body.removeAction(forKey: bodySquashKey)
        for n in [leftEye, rightEye] { n.removeAction(forKey: eyeActionKey) }
        for n in [leftPupil, rightPupil] { n.removeAction(forKey: pupilActionKey) }
        stopFootAnimation()
        mascotNode.zRotation = 0
        body.xScale = 1
        body.yScale = 1
        body.zRotation = 0
        propLabel.isHidden = true
        userMoveDirection = 0

        let controller = DinoGameController(
            scene: self,
            mascotNode: mascotNode,
            mascotSize: mascotSize,
            palette: currentColor(),
            bounds: size,
            ground: groundY,
            settings: settings
        )
        game = controller
        controller.start()
    }

    private func tearDownGame() {
        game?.stop()
        game = nil
        positionAtStart()
    }

    private func applyPendingClaudeState() {
        if let activity = pendingActivity {
            pendingActivity = nil
            setActivity(activity)
        }
        if let pending = pendingState {
            pendingState = nil
            setState(pending)
        }
    }

    func tryJump() {
        if state == .playing {
            game?.jump()
        }
    }

    func tryRestart() {
        if state == .playing {
            game?.restart()
        }
    }

    /// User-initiated exit from the dino game. Bypasses the in-game
    /// deferral guard in `setState(_:)` so the scene can actually leave
    /// the `.playing` state.
    func exitGame() {
        guard state == .playing else { return }
        let leavingPlaying = true
        state = .idle
        clearAutoMotion()
        userMoveDirection = 0
        tearDownGame()
        sceneDelegate?.mascotScene(self, didChangeStateTo: state)
        if leavingPlaying { applyPendingClaudeState() }
    }

    var isGameOver: Bool { game?.isOver ?? false }

    private func clearAutoMotion() {
        mascotNode.removeAction(forKey: walkActionKey)
        stopFootAnimation()
        mascotNode.zRotation = 0
        positionAtStart()
    }

    private func startAutoMotionForActivity() {
        let mult = currentActivity.speedMultiplier
        if mult > 0 {
            startFootAnimation()
            scheduleNextLeg()
        }
        // mult == 0 → decoration handles motion; nothing else to do here
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
        if state == .playing { return }
        let up = SKAction.moveBy(x: 0, y: 36, duration: 0.18)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -36, duration: 0.18)
        down.timingMode = .easeIn
        mascotNode.run(SKAction.sequence([up, down]), withKey: jumpActionKey)
    }

    func notify() {
        if state == .playing { return }
        let up = SKAction.moveBy(x: 0, y: 14, duration: 0.1)
        let down = SKAction.moveBy(x: 0, y: -14, duration: 0.1)
        mascotNode.run(SKAction.sequence([up, down, up, down]))
    }

    // MARK: - Activity / customization

    func setActivity(_ activity: MascotActivity) {
        if state == .playing {
            pendingActivity = activity
            return
        }
        guard currentActivity != activity else { return }
        currentActivity = activity
        propLabel.text = activity.prop
        propLabel.isHidden = activity.prop.isEmpty
        applyActivityDecoration()
        if state == .walking {
            mascotNode.removeAction(forKey: walkActionKey)
            startAutoMotionForActivity()
        }
    }

    func setSize(points: Int) {
        let clamped = CGFloat(max(MascotSettings.sizeRange.first!,
                                  min(MascotSettings.sizeRange.last!, points)))
        guard abs(clamped - mascotSize) > 0.5 else { return }
        mascotSize = clamped
        rebuildMascot()
    }

    func setColor(index: Int) {
        let count = MascotPalette.colors.count
        guard count > 0 else { return }
        let normalized = ((index % count) + count) % count
        guard normalized != colorIndex else { return }
        colorIndex = normalized
        let palette = MascotPalette.colors[normalized]
        body.fillColor = palette.body
        leftFoot.fillColor = palette.foot
        rightFoot.fillColor = palette.foot
        // Variant decorations may derive accents from the palette
        // (e.g. dog snout uses foot color), so rebuild them too.
        decorationNode.removeAllChildren()
        variant.buildDecorations(into: decorationNode, size: mascotSize, palette: palette)
    }

    func setVariant(index: Int) {
        let count = MascotVariant.allCases.count
        guard count > 0 else { return }
        let normalized = ((index % count) + count) % count
        guard normalized != variantIndex else { return }
        variantIndex = normalized
        rebuildMascot()
        // rebuildMascot resets eye/foot positions for the new silhouette;
        // re-apply the current activity so its decoration (pupil scan, blink,
        // squash, etc.) re-anchors to the new eyeY.
        applyActivityDecoration()
    }

    private func applyActivityDecoration() {
        // Reset prior decoration state — both the actions and any leftover
        // transform/position offset they may have accumulated.
        mascotNode.removeAction(forKey: decorationActionKey)
        body.removeAction(forKey: bodySquashKey)
        for n in [leftEye, rightEye] { n.removeAction(forKey: eyeActionKey) }
        for n in [leftPupil, rightPupil] { n.removeAction(forKey: pupilActionKey) }
        mascotNode.zRotation = 0
        mascotNode.position.y = groundY
        body.xScale = 1
        body.yScale = 1
        body.zRotation = 0
        leftEye.yScale = 1
        rightEye.yScale = 1
        // Reset pupil positions to nominal (rebuildMascot already centers them)
        let s = mascotSize
        let pupilR = s * 0.12 * 0.55
        let eyeY = variant.eyeY(size: s)
        leftPupil.position = CGPoint(x: -s * 0.2 + pupilR * 0.3, y: eyeY)
        rightPupil.position = CGPoint(x: s * 0.2 + pupilR * 0.3, y: eyeY)

        switch currentActivity {
        case .idle:
            // Idle isn't motionless — the mascot blinks and glances around
            // so it doesn't look frozen between Claude turns. The varied
            // wait durations make the rhythm feel irregular instead of
            // metronomic.
            let blink = SKAction.sequence([
                SKAction.scaleY(to: 0.12, duration: 0.07),
                SKAction.scaleY(to: 1.0, duration: 0.09),
            ])
            let blinkPattern = SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: 3.6),
                blink,
                SKAction.wait(forDuration: 4.2),
                blink,
                SKAction.wait(forDuration: 2.7),
                blink,
                blink,                      // occasional double-blink
                SKAction.wait(forDuration: 5.3),
            ]))
            leftEye.run(blinkPattern, withKey: eyeActionKey)
            rightEye.run(blinkPattern, withKey: eyeActionKey)

            let glance = SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: 2.4),
                SKAction.moveBy(x: 3, y: 0, duration: 0.28),    // look right
                SKAction.wait(forDuration: 1.3),
                SKAction.moveBy(x: -6, y: 0, duration: 0.4),    // look left
                SKAction.wait(forDuration: 1.6),
                SKAction.moveBy(x: 3, y: 0, duration: 0.28),    // back to center
                SKAction.wait(forDuration: 4.5),
            ]))
            leftPupil.run(glance, withKey: pupilActionKey)
            rightPupil.run(glance, withKey: pupilActionKey)

        case .thinking:
            let bob = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 4, duration: 0.6),
                SKAction.moveBy(x: 0, y: -4, duration: 0.6),
            ])
            mascotNode.run(.repeatForever(bob), withKey: decorationActionKey)

        case .reading:
            let scan = SKAction.sequence([
                SKAction.moveBy(x: 3, y: 0, duration: 0.4),
                SKAction.moveBy(x: -6, y: 0, duration: 0.5),
                SKAction.moveBy(x: 3, y: 0, duration: 0.4),
            ])
            leftPupil.run(.repeatForever(scan), withKey: pupilActionKey)
            rightPupil.run(.repeatForever(scan), withKey: pupilActionKey)

        case .coding:
            let typing = SKAction.sequence([
                SKAction.scaleX(to: 1.06, y: 0.94, duration: 0.08),
                SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.08),
                SKAction.scaleX(to: 1.06, y: 0.94, duration: 0.08),
                SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.18),
            ])
            body.run(.repeatForever(typing), withKey: bodySquashKey)

        case .running:
            let lean = SKAction.sequence([
                SKAction.rotate(toAngle: -0.08, duration: 0.18),
                SKAction.rotate(toAngle: 0, duration: 0.18),
            ])
            body.run(.repeatForever(lean), withKey: bodySquashKey)

        case .planning:
            let tilt = SKAction.sequence([
                SKAction.rotate(toAngle: .pi / 14, duration: 0.8),
                SKAction.rotate(toAngle: -.pi / 14, duration: 1.4),
                SKAction.rotate(toAngle: 0, duration: 0.6),
            ])
            body.run(.repeatForever(tilt), withKey: bodySquashKey)

        case .browsing:
            let squint = SKAction.sequence([
                SKAction.scaleY(to: 0.4, duration: 0.5),
                SKAction.scaleY(to: 1.0, duration: 0.5),
                SKAction.wait(forDuration: 0.4),
            ])
            leftEye.run(.repeatForever(squint), withKey: eyeActionKey)
            rightEye.run(.repeatForever(squint), withKey: eyeActionKey)

        case .deepThink:
            let longBob = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 6, duration: 1.4),
                SKAction.moveBy(x: 0, y: -6, duration: 1.4),
            ])
            mascotNode.run(.repeatForever(longBob), withKey: decorationActionKey)
            let blink = SKAction.sequence([
                SKAction.scaleY(to: 0.15, duration: 0.15),
                SKAction.scaleY(to: 1.0, duration: 0.15),
                SKAction.wait(forDuration: 2.5),
            ])
            leftEye.run(.repeatForever(blink), withKey: eyeActionKey)
            rightEye.run(.repeatForever(blink), withKey: eyeActionKey)

        case .compacting:
            mascotNode.run(.repeatForever(
                SKAction.rotate(byAngle: 2 * .pi, duration: 3.0)
            ), withKey: decorationActionKey)

        case .dancing:
            let hop = SKAction.sequence([
                SKAction.moveBy(x: 6, y: 12, duration: 0.18),
                SKAction.moveBy(x: 0, y: -12, duration: 0.15),
                SKAction.moveBy(x: -12, y: 12, duration: 0.18),
                SKAction.moveBy(x: 0, y: -12, duration: 0.15),
                SKAction.moveBy(x: 6, y: 0, duration: 0.1),
            ])
            mascotNode.run(.repeatForever(hop), withKey: decorationActionKey)
        }
    }

    // MARK: - Petting

    /// Per-frame tick that watches for a back-and-forth gesture over the
    /// head and ramps `pettingLevel` up/down. Visual reaction (squint /
    /// sway / tail wag) is written directly here so it fades smoothly with
    /// the level instead of toggling on a boolean.
    private func tickPetting(currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastTickTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = max(0, currentTime - lastTickTime)
        }
        lastTickTime = currentTime

        // Petting only engages while the dog is just being a dog — not
        // during the runner game, control mode, or any non-idle activity
        // (those run their own SKActions on the body/eyes that would
        // fight the per-frame writes below).
        let active = (state == .idle || state == .walking) && currentActivity == .idle

        if active, let mouse = mouseLocationProvider?() {
            let frame = mascotFrameInScene()
            let headPad: CGFloat = 6
            let headRect = CGRect(
                x: frame.minX - headPad,
                y: frame.minY + frame.height * 0.45,
                width: frame.width + 2 * headPad,
                height: frame.height * 0.55 + headPad
            )
            if headRect.contains(mouse) {
                if let last = lastMouseSceneX {
                    let delta = mouse.x - last
                    if abs(delta) >= 0.5 {
                        let dir: Int = delta > 0 ? 1 : -1
                        if lastDirection != 0 && dir != lastDirection {
                            reversalTimes.append(currentTime)
                        }
                        lastDirection = dir
                    }
                }
                lastMouseSceneX = mouse.x
            } else {
                lastMouseSceneX = nil
                lastDirection = 0
            }
        } else {
            lastMouseSceneX = nil
            lastDirection = 0
        }

        // Sliding 1.5s window of recent reversals.
        let windowStart = currentTime - 1.5
        while let first = reversalTimes.first, first < windowStart {
            reversalTimes.removeFirst()
        }

        if !active {
            // Snap off rather than fighting another activity's SKActions
            // mid-fade. (Active states/idle activity are checked above.)
            pettingLevel = 0
        } else if reversalTimes.count >= 2 {
            pettingLevel = min(1, pettingLevel + CGFloat(dt) * 1.2)
        } else {
            pettingLevel *= CGFloat(exp(-dt / 0.5))
            if pettingLevel < 0.005 { pettingLevel = 0 }
        }

        applyPettingReaction(currentTime: currentTime)
        prevPettingLevel = pettingLevel
    }

    private func applyPettingReaction(currentTime: TimeInterval) {
        let level = pettingLevel

        if level > 0 && prevPettingLevel == 0 {
            // Engaging: take over the eyes from the idle blink/glance so
            // those SKActions don't fight our per-frame writes.
            leftEye.removeAction(forKey: eyeActionKey)
            rightEye.removeAction(forKey: eyeActionKey)
            leftPupil.removeAction(forKey: pupilActionKey)
            rightPupil.removeAction(forKey: pupilActionKey)
        }

        if level > 0 {
            let squint = 1 - 0.7 * level
            leftEye.yScale = squint
            rightEye.yScale = squint
            leftPupil.yScale = squint
            rightPupil.yScale = squint
            body.zRotation = CGFloat(sin(currentTime * 6)) * 0.10 * level
        } else if prevPettingLevel > 0 {
            // Releasing: restore resting visuals and let the activity
            // decoration repopulate the eye/pupil actions.
            leftEye.yScale = 1
            rightEye.yScale = 1
            leftPupil.yScale = 1
            rightPupil.yScale = 1
            body.zRotation = 0
            applyActivityDecoration()
        }

        // Pause walking while being meaningfully petted — the dog stops to
        // enjoy it instead of moonwalking through the gesture.
        let shouldPause = state == .walking && level > 0.15
        if shouldPause && !walkPaused {
            mascotNode.action(forKey: walkActionKey)?.speed = 0
            stopFootAnimation()
            walkPaused = true
        } else if !shouldPause && walkPaused {
            mascotNode.action(forKey: walkActionKey)?.speed = 1
            if state == .walking {
                startFootAnimation()
            }
            walkPaused = false
        }
    }

    // MARK: - User-driven control

    func mascotFrameInScene() -> CGRect {
        let s = mascotSize
        return CGRect(
            x: mascotNode.position.x - s / 2,
            y: mascotNode.position.y,
            width: s,
            height: s
        )
    }

    func setUserMove(direction dir: CGFloat) {
        guard state == .controlled else { return }
        let normalized: CGFloat = dir > 0 ? 1 : (dir < 0 ? -1 : 0)
        guard normalized != userMoveDirection else { return }
        userMoveDirection = normalized
        mascotNode.removeAction(forKey: userMoveActionKey)

        if normalized == 0 {
            stopFootAnimation()
            return
        }

        mascotNode.xScale = normalized > 0 ? 1 : -1
        let margin: CGFloat = mascotSize / 2 + 8
        let leftEdge = margin
        let rightEdge = max(margin + 1, size.width - margin)
        let target = normalized > 0 ? rightEdge : leftEdge
        let distance = max(0, abs(target - mascotNode.position.x))
        guard distance > 0.5 else {
            stopFootAnimation()
            return
        }
        let duration = TimeInterval(distance / baseWalkSpeed)
        startFootAnimation()
        let move = SKAction.moveTo(x: target, duration: duration)
        let stop = SKAction.run { [weak self] in
            self?.stopFootAnimation()
            self?.userMoveDirection = 0
        }
        mascotNode.run(SKAction.sequence([move, stop]), withKey: userMoveActionKey)
    }

    @discardableResult
    func userJump() -> Bool {
        guard state == .controlled else { return false }
        if mascotNode.action(forKey: jumpActionKey) != nil { return false }
        let up = SKAction.moveBy(x: 0, y: 36, duration: 0.18)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -36, duration: 0.18)
        down.timingMode = .easeIn
        mascotNode.run(SKAction.sequence([up, down]), withKey: jumpActionKey)
        return true
    }

    private func clampCurrentX() {
        guard size.width > mascotSize else { return }
        let margin: CGFloat = mascotSize / 2 + 8
        let leftEdge = margin
        let rightEdge = max(margin + 1, size.width - margin)
        let x = min(max(mascotNode.position.x, leftEdge), rightEdge)
        if x != mascotNode.position.x {
            mascotNode.position.x = x
            if state == .controlled, userMoveDirection != 0 {
                let dir = userMoveDirection
                userMoveDirection = 0
                setUserMove(direction: dir)
            }
        }
    }
}

private extension CGFloat {
    /// Returns `self` if non-zero, otherwise the fallback. Lets us express
    /// "use this multiplier if it's meaningful, else 1".
    func nonZeroOr(_ fallback: CGFloat) -> CGFloat {
        self == 0 ? fallback : self
    }
}
