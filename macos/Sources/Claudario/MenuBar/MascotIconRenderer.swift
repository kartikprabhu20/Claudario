import AppKit
import SpriteKit

enum MascotIconRenderer {
    /// Renders the given variant + color into an NSImage suitable for an
    /// NSStatusItem button. Reuses the overlay's path and decoration code
    /// (an offscreen SKView snapshot) so the menu-bar icon stays in sync
    /// with the on-screen mascot automatically.
    static func render(variant: MascotVariant, color: MascotColor, pointSize: CGFloat) -> NSImage {
        // Render at 2x physical resolution so the icon stays crisp on
        // retina menu bars; downscale via NSImage.size below.
        let scale: CGFloat = 2.0
        let s = pointSize * scale

        // Canvas needs vertical headroom (cat/owl tufts reach s*1.05,
        // robot antenna s*0.98) and a sliver of horizontal padding.
        let canvasPixelSize = CGSize(width: s * 1.20, height: s * 1.15)
        let canvasPointSize = CGSize(
            width: canvasPixelSize.width / scale,
            height: canvasPixelSize.height / scale)

        let scene = SKScene(size: canvasPixelSize)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill

        // Root sits centered, body baseline ~1 px above canvas bottom.
        let root = SKNode()
        root.position = CGPoint(x: canvasPixelSize.width / 2, y: scale)
        scene.addChild(root)

        let body = SKShapeNode(path: variant.bodyPath(size: s))
        body.fillColor = color.body
        body.strokeColor = .clear
        body.lineWidth = 0
        body.isAntialiased = true
        root.addChild(body)

        variant.buildDecorations(into: root, size: s, palette: color)

        // Static eyes — no animation in the menu-bar icon. Anchors match
        // the overlay's default eye positions so panda eye-patches and
        // similar decorations still frame them correctly.
        let eyeY = variant.eyeY(size: s)
        for dx in [-s * 0.18, s * 0.18] {
            let eye = SKShapeNode(circleOfRadius: s * 0.06)
            eye.fillColor = .black
            eye.strokeColor = .clear
            eye.isAntialiased = true
            eye.position = CGPoint(x: dx, y: eyeY)
            root.addChild(eye)
        }

        let view = SKView(frame: CGRect(origin: .zero, size: canvasPixelSize))
        view.allowsTransparency = true
        view.presentScene(scene)

        guard let texture = view.texture(from: scene, crop: CGRect(origin: .zero, size: canvasPixelSize)) else {
            return NSImage(size: canvasPointSize)
        }
        let cgImage = texture.cgImage()

        let image = NSImage(cgImage: cgImage, size: canvasPointSize)
        image.isTemplate = false
        return image
    }
}
