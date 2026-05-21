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

        let rootPosition = CGPoint(x: canvasPixelSize.width / 2, y: scale)
        return renderScene(
            variant: variant,
            color: color,
            mascotSize: s,
            canvasPixelSize: canvasPixelSize,
            canvasPointSize: canvasPointSize,
            rootPosition: rootPosition)
    }

    /// Renders the variant + color into a square NSImage suitable for use
    /// as `NSApp.applicationIconImage` (About dialogs, NSAlerts, etc.).
    /// Uses a square canvas with the mascot centered, sized so its widest
    /// extent (dog ears reach ±s*0.62) takes ~80% of the canvas width.
    static func renderAppIcon(variant: MascotVariant, color: MascotColor, pointSize: CGFloat) -> NSImage {
        let scale: CGFloat = 2.0
        let canvas = pointSize * scale
        let canvasPixelSize = CGSize(width: canvas, height: canvas)
        let canvasPointSize = CGSize(width: pointSize, height: pointSize)

        // 80% of canvas / 1.24 (widest variant extent) ≈ 0.645.
        let s = canvas * 0.645

        // Vertically center the body's bounding box (feet at y=0, top ~s*0.85).
        let bodyTop = s * 0.85
        let rootPosition = CGPoint(x: canvas / 2, y: (canvas - bodyTop) / 2)

        return renderScene(
            variant: variant,
            color: color,
            mascotSize: s,
            canvasPixelSize: canvasPixelSize,
            canvasPointSize: canvasPointSize,
            rootPosition: rootPosition)
    }

    /// Renders a square CGImage at exactly `pixelSize × pixelSize` pixels for
    /// iconset PNG export (the `--export-iconset` build-time mode). No Retina
    /// doubling — the caller chooses the pixel resolution directly.
    static func renderAppIconCGImage(variant: MascotVariant, color: MascotColor, pixelSize: CGFloat) -> CGImage? {
        let canvasPixelSize = CGSize(width: pixelSize, height: pixelSize)
        let s = pixelSize * 0.645
        let bodyTop = s * 0.85
        let rootPosition = CGPoint(x: pixelSize / 2, y: (pixelSize - bodyTop) / 2)
        return buildCGImage(
            variant: variant,
            color: color,
            mascotSize: s,
            canvasPixelSize: canvasPixelSize,
            rootPosition: rootPosition)
    }

    private static func renderScene(
        variant: MascotVariant,
        color: MascotColor,
        mascotSize s: CGFloat,
        canvasPixelSize: CGSize,
        canvasPointSize: CGSize,
        rootPosition: CGPoint
    ) -> NSImage {
        guard let cgImage = buildCGImage(
            variant: variant,
            color: color,
            mascotSize: s,
            canvasPixelSize: canvasPixelSize,
            rootPosition: rootPosition)
        else {
            return NSImage(size: canvasPointSize)
        }
        let image = NSImage(cgImage: cgImage, size: canvasPointSize)
        image.isTemplate = false
        return image
    }

    private static func buildCGImage(
        variant: MascotVariant,
        color: MascotColor,
        mascotSize s: CGFloat,
        canvasPixelSize: CGSize,
        rootPosition: CGPoint
    ) -> CGImage? {
        let scene = SKScene(size: canvasPixelSize)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill

        let root = SKNode()
        root.position = rootPosition
        scene.addChild(root)

        let body = SKShapeNode(path: variant.bodyPath(size: s))
        body.fillColor = color.body
        body.strokeColor = .clear
        body.lineWidth = 0
        body.isAntialiased = true
        root.addChild(body)

        variant.buildDecorations(into: root, size: s, palette: color)

        // Static eyes — no animation. Anchors match the overlay's default
        // eye positions so panda eye-patches and similar decorations still
        // frame them correctly.
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
            return nil
        }
        return texture.cgImage()
    }
}
