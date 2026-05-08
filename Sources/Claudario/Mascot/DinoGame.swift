import AppKit
import SpriteKit

/// Side-scrolling minigame inspired by the Chrome dino runner. The mascot
/// stays pinned to the left of the Dock strip; obstacles scroll in from
/// the right and the player jumps with the up-arrow key. The controller
/// is owned by `MascotScene` and lives only while `state == .playing`.
final class DinoGameController {
    weak var scene: MascotScene?
    let mascotNode: SKNode
    let mascotSize: CGFloat
    let palette: MascotColor
    let bounds: CGSize
    let ground: CGFloat
    let settings: MascotSettings

    private var obstacles: [SKShapeNode] = []
    private let scoreLabel = SKLabelNode()
    private let hintLabel  = SKLabelNode()
    private let groundLine = SKShapeNode()

    private var lastTick: TimeInterval = 0
    private var spawnAccumulator: CGFloat = 0
    private var nextSpawnInterval: CGFloat = 1.6
    private var scrollSpeed: CGFloat = 240
    private(set) var score: Int = 0
    private(set) var isOver: Bool = false

    private var verticalVelocity: CGFloat = 0
    private let jumpVelocity: CGFloat = 600
    private let gravity: CGFloat = -1800

    private let zGround: CGFloat = 5
    private let zObstacle: CGFloat = 6
    private let zHUD: CGFloat = 50

    private var mascotX: CGFloat { mascotSize / 2 + 24 }

    init(scene: MascotScene,
         mascotNode: SKNode,
         mascotSize: CGFloat,
         palette: MascotColor,
         bounds: CGSize,
         ground: CGFloat,
         settings: MascotSettings) {
        self.scene = scene
        self.mascotNode = mascotNode
        self.mascotSize = mascotSize
        self.palette = palette
        self.bounds = bounds
        self.ground = ground
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        guard let scene = scene else { return }

        mascotNode.position = CGPoint(x: mascotX, y: ground)
        mascotNode.xScale = 1
        mascotNode.zRotation = 0

        let lineRect = CGRect(x: 0, y: -1, width: bounds.width, height: 1)
        groundLine.path = CGPath(rect: lineRect, transform: nil)
        groundLine.fillColor = palette.foot.withAlphaComponent(0.4)
        groundLine.strokeColor = .clear
        groundLine.position = CGPoint(x: 0, y: ground)
        groundLine.zPosition = zGround
        scene.addChild(groundLine)

        scoreLabel.fontName = "Menlo-Bold"
        scoreLabel.fontSize = 14
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.verticalAlignmentMode = .bottom
        scoreLabel.position = CGPoint(x: bounds.width - 16, y: 8)
        scoreLabel.zPosition = zHUD
        scene.addChild(scoreLabel)

        hintLabel.fontName = "Menlo-Bold"
        hintLabel.fontSize = 13
        hintLabel.fontColor = NSColor.white
        hintLabel.horizontalAlignmentMode = .center
        hintLabel.verticalAlignmentMode = .center
        hintLabel.position = CGPoint(x: bounds.width / 2, y: bounds.height * 0.62)
        hintLabel.zPosition = zHUD
        hintLabel.isHidden = true
        scene.addChild(hintLabel)

        resetRun()
    }

    func stop() {
        groundLine.removeFromParent()
        scoreLabel.removeFromParent()
        hintLabel.removeFromParent()
        for obstacle in obstacles { obstacle.removeFromParent() }
        obstacles.removeAll()
    }

    func restart() {
        guard isOver else { return }
        for obstacle in obstacles { obstacle.removeFromParent() }
        obstacles.removeAll()
        hintLabel.isHidden = true
        mascotNode.position = CGPoint(x: mascotX, y: ground)
        verticalVelocity = 0
        resetRun()
    }

    private func resetRun() {
        isOver = false
        score = 0
        scrollSpeed = 240
        nextSpawnInterval = 1.6
        spawnAccumulator = 0
        lastTick = 0
        updateScoreLabel()
    }

    // MARK: - Input

    func jump() {
        guard !isOver else { return }
        // Single jump per landing: only allow when feet are on the ground.
        guard mascotNode.position.y <= ground + 0.5, verticalVelocity == 0 else { return }
        verticalVelocity = jumpVelocity
    }

    // MARK: - Tick

    func tick(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if lastTick == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = CGFloat(min(1.0 / 30.0, currentTime - lastTick))
        }
        lastTick = currentTime

        if isOver { return }

        // Vertical physics
        verticalVelocity += gravity * dt
        var y = mascotNode.position.y + verticalVelocity * dt
        if y <= ground {
            y = ground
            verticalVelocity = 0
        }
        mascotNode.position.y = y

        // Spawn new obstacles on a decaying interval
        spawnAccumulator += dt
        if spawnAccumulator >= nextSpawnInterval {
            spawnAccumulator = 0
            spawnObstacle()
            // Shorten the gap between obstacles as the score climbs, but
            // never below 0.7s — below that the run becomes unsurvivable.
            let progress = min(CGFloat(score) / 30.0, 1.0)
            nextSpawnInterval = 1.6 - 0.9 * progress + CGFloat.random(in: -0.15...0.15)
            nextSpawnInterval = max(0.7, nextSpawnInterval)
        }

        // Scroll obstacles left and reap any that exited the strip
        let dx = scrollSpeed * dt
        var stillAlive: [SKShapeNode] = []
        for obstacle in obstacles {
            obstacle.position.x -= dx
            if obstacle.position.x + obstacle.frame.width < 0 {
                obstacle.removeFromParent()
                score += 1
                updateScoreLabel()
            } else {
                stillAlive.append(obstacle)
            }
        }
        obstacles = stillAlive

        // Ramp up speed slowly with score, capped to keep the game playable
        scrollSpeed = min(420, 240 + CGFloat(score) * 4)

        // Collision check
        let mascotRect = CGRect(
            x: mascotNode.position.x - mascotSize / 2 + 6,
            y: mascotNode.position.y + 4,
            width: mascotSize - 12,
            height: mascotSize - 8
        )
        for obstacle in obstacles {
            if obstacle.frame.intersects(mascotRect) {
                endGame()
                return
            }
        }
    }

    // MARK: - Helpers

    private func spawnObstacle() {
        guard let scene = scene else { return }
        let isTall = Bool.random()
        let height: CGFloat = isTall ? mascotSize * 0.64 : mascotSize * 0.34
        let width: CGFloat = mascotSize * 0.32
        let rect = CGRect(x: -width / 2, y: 0, width: width, height: height)
        let radius = min(width, height) * 0.3
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        let node = SKShapeNode(path: path)
        node.fillColor = palette.body
        node.strokeColor = palette.foot.withAlphaComponent(0.6)
        node.lineWidth = 1
        node.position = CGPoint(x: bounds.width + width, y: ground)
        node.zPosition = zObstacle
        scene.addChild(node)
        obstacles.append(node)
    }

    private func updateScoreLabel() {
        if score > settings.dinoHighScore {
            settings.dinoHighScore = score
        }
        let high = settings.dinoHighScore
        scoreLabel.text = String(format: "SCORE %03d HI %03d", score, high)
    }

    private func endGame() {
        isOver = true
        if score > settings.dinoHighScore {
            settings.dinoHighScore = score
        }
        updateScoreLabel()
        hintLabel.text = "GAME OVER · R to restart · Esc to exit"
        hintLabel.isHidden = false
    }
}
