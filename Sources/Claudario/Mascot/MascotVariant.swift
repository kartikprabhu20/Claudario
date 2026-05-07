import AppKit
import SpriteKit

enum MascotVariant: Int, CaseIterable {
    case classic, egg, cat, dog, owl, panda, robot

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .egg:     return "Egg"
        case .cat:     return "Cat"
        case .dog:     return "Dog"
        case .owl:     return "Owl"
        case .panda:   return "Panda"
        case .robot:   return "Robot"
        }
    }

    /// Body silhouette path. Lowest point sits at y=0 so feet attach naturally;
    /// horizontally centered on x=0.
    func bodyPath(size s: CGFloat) -> CGPath {
        switch self {
        case .classic:
            return CGPath(
                roundedRect: CGRect(x: -s / 2, y: 0, width: s, height: s),
                cornerWidth: s * 0.3, cornerHeight: s * 0.3, transform: nil)

        case .egg:
            // Asymmetric oval: fat round bottom, narrower tapered top.
            // Built from 4 cubic bezier segments around a vertical axis.
            let h = s
            let bottomR: CGFloat = s * 0.45
            let topR: CGFloat = s * 0.32
            let waistY: CGFloat = h * 0.42

            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addCurve(
                to: CGPoint(x: bottomR, y: waistY),
                control1: CGPoint(x: bottomR * 0.9, y: 0),
                control2: CGPoint(x: bottomR, y: waistY * 0.4))
            path.addCurve(
                to: CGPoint(x: 0, y: h),
                control1: CGPoint(x: bottomR, y: waistY + (h - waistY) * 0.35),
                control2: CGPoint(x: topR * 0.9, y: h))
            path.addCurve(
                to: CGPoint(x: -bottomR, y: waistY),
                control1: CGPoint(x: -topR * 0.9, y: h),
                control2: CGPoint(x: -bottomR, y: waistY + (h - waistY) * 0.35))
            path.addCurve(
                to: CGPoint(x: 0, y: 0),
                control1: CGPoint(x: -bottomR, y: waistY * 0.4),
                control2: CGPoint(x: -bottomR * 0.9, y: 0))
            path.closeSubpath()
            return path

        case .cat:
            // Single continuous outline: rounded-bottom body with two pointed
            // ears protruding from the top corners and a shallow valley
            // between them. No internal subpaths so the stroke draws a clean
            // cat-head silhouette.
            let path = CGMutablePath()
            let corner: CGFloat = s * 0.18
            let bodyTop: CGFloat = s * 0.70

            path.move(to: CGPoint(x: -s / 2 + corner, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: -s / 2, y: corner),
                control: CGPoint(x: -s / 2, y: 0))
            path.addLine(to: CGPoint(x: -s / 2, y: bodyTop))
            path.addLine(to: CGPoint(x: -s * 0.30, y: s * 1.05))   // left ear tip
            path.addLine(to: CGPoint(x: -s * 0.10, y: bodyTop))    // valley
            path.addLine(to: CGPoint(x:  s * 0.10, y: bodyTop))
            path.addLine(to: CGPoint(x:  s * 0.30, y: s * 1.05))   // right ear tip
            path.addLine(to: CGPoint(x:  s / 2, y: bodyTop))
            path.addLine(to: CGPoint(x:  s / 2, y: corner))
            path.addQuadCurve(
                to: CGPoint(x: s / 2 - corner, y: 0),
                control: CGPoint(x: s / 2, y: 0))
            path.addLine(to: CGPoint(x: -s / 2 + corner, y: 0))
            path.closeSubpath()
            return path

        case .dog:
            // Floppy-eared head: rounded body with two oval ear bumps
            // protruding outward from the upper sides. Single continuous
            // outline avoids internal stroke artifacts.
            let path = CGMutablePath()
            let corner: CGFloat = s * 0.18
            let bodyTop: CGFloat = s * 0.85

            path.move(to: CGPoint(x: -s / 2 + corner, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: -s / 2, y: corner),
                control: CGPoint(x: -s / 2, y: 0))
            path.addLine(to: CGPoint(x: -s / 2, y: s * 0.20))
            // Left floppy ear (out, around, back)
            path.addQuadCurve(
                to: CGPoint(x: -s * 0.62, y: s * 0.22),
                control: CGPoint(x: -s * 0.60, y: s * 0.10))
            path.addQuadCurve(
                to: CGPoint(x: -s * 0.62, y: s * 0.55),
                control: CGPoint(x: -s * 0.74, y: s * 0.40))
            path.addQuadCurve(
                to: CGPoint(x: -s / 2, y: s * 0.65),
                control: CGPoint(x: -s * 0.55, y: s * 0.66))
            // Up to top-left corner
            path.addLine(to: CGPoint(x: -s / 2, y: bodyTop - corner))
            path.addQuadCurve(
                to: CGPoint(x: -s / 2 + corner, y: bodyTop),
                control: CGPoint(x: -s / 2, y: bodyTop))
            // Across top
            path.addLine(to: CGPoint(x: s / 2 - corner, y: bodyTop))
            path.addQuadCurve(
                to: CGPoint(x: s / 2, y: bodyTop - corner),
                control: CGPoint(x: s / 2, y: bodyTop))
            // Down right side, then mirror floppy ear
            path.addLine(to: CGPoint(x: s / 2, y: s * 0.65))
            path.addQuadCurve(
                to: CGPoint(x: s * 0.62, y: s * 0.55),
                control: CGPoint(x: s * 0.55, y: s * 0.66))
            path.addQuadCurve(
                to: CGPoint(x: s * 0.62, y: s * 0.22),
                control: CGPoint(x: s * 0.74, y: s * 0.40))
            path.addQuadCurve(
                to: CGPoint(x: s / 2, y: s * 0.20),
                control: CGPoint(x: s * 0.60, y: s * 0.10))
            // Down to bottom-right corner
            path.addLine(to: CGPoint(x: s / 2, y: corner))
            path.addQuadCurve(
                to: CGPoint(x: s / 2 - corner, y: 0),
                control: CGPoint(x: s / 2, y: 0))
            path.addLine(to: CGPoint(x: -s / 2 + corner, y: 0))
            path.closeSubpath()
            return path

        case .owl:
            // Round-bottomed body with two pointed ear tufts on the upper
            // sides and a small valley between them.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: s * 0.48, y: s * 0.40),
                control: CGPoint(x: s * 0.52, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: s * 0.40, y: s * 0.85),
                control: CGPoint(x: s * 0.55, y: s * 0.68))
            path.addLine(to: CGPoint(x: s * 0.32, y: s * 1.05))   // right tuft
            path.addLine(to: CGPoint(x: s * 0.18, y: s * 0.92))
            path.addQuadCurve(
                to: CGPoint(x: -s * 0.18, y: s * 0.92),
                control: CGPoint(x: 0, y: s * 0.84))
            path.addLine(to: CGPoint(x: -s * 0.32, y: s * 1.05))  // left tuft
            path.addLine(to: CGPoint(x: -s * 0.40, y: s * 0.85))
            path.addQuadCurve(
                to: CGPoint(x: -s * 0.48, y: s * 0.40),
                control: CGPoint(x: -s * 0.55, y: s * 0.68))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: 0),
                control: CGPoint(x: -s * 0.52, y: 0))
            path.closeSubpath()
            return path

        case .panda:
            // Slightly flattened oval body. Ears, eye patches, and nose are
            // added as fixed-color decorations so they stay black under any
            // palette.
            return CGPath(
                ellipseIn: CGRect(x: -s * 0.50, y: 0, width: s, height: s * 0.92),
                transform: nil)

        case .robot:
            // Boxy chassis with a thin antenna stem rising from the top.
            // Single continuous outline so the antenna looks attached.
            let path = CGMutablePath()
            let corner: CGFloat = s * 0.06
            let bodyTop: CGFloat = s * 0.85
            let stemHalfW: CGFloat = s * 0.06
            let stemTop: CGFloat = s * 0.98

            path.move(to: CGPoint(x: -s / 2 + corner, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: -s / 2, y: corner),
                control: CGPoint(x: -s / 2, y: 0))
            path.addLine(to: CGPoint(x: -s / 2, y: bodyTop - corner))
            path.addQuadCurve(
                to: CGPoint(x: -s / 2 + corner, y: bodyTop),
                control: CGPoint(x: -s / 2, y: bodyTop))
            path.addLine(to: CGPoint(x: -stemHalfW, y: bodyTop))
            path.addLine(to: CGPoint(x: -stemHalfW, y: stemTop))
            path.addLine(to: CGPoint(x:  stemHalfW, y: stemTop))
            path.addLine(to: CGPoint(x:  stemHalfW, y: bodyTop))
            path.addLine(to: CGPoint(x:  s / 2 - corner, y: bodyTop))
            path.addQuadCurve(
                to: CGPoint(x: s / 2, y: bodyTop - corner),
                control: CGPoint(x: s / 2, y: bodyTop))
            path.addLine(to: CGPoint(x: s / 2, y: corner))
            path.addQuadCurve(
                to: CGPoint(x: s / 2 - corner, y: 0),
                control: CGPoint(x: s / 2, y: 0))
            path.addLine(to: CGPoint(x: -s / 2 + corner, y: 0))
            path.closeSubpath()
            return path
        }
    }

    /// Eye-center Y, relative to the body's bottom (y=0).
    func eyeY(size s: CGFloat) -> CGFloat {
        switch self {
        case .classic: return s * 0.70
        case .egg:     return s * 0.62
        case .cat:     return s * 0.45
        case .dog:     return s * 0.55
        case .owl:     return s * 0.55
        case .panda:   return s * 0.55
        case .robot:   return s * 0.55
        }
    }

    /// Vertical offset for foot attachment (y=0 = body's bottom edge).
    func footY(size _: CGFloat) -> CGFloat { 0 }

    /// Adds variant-specific decorations (inner ears, nose, whiskers, etc.)
    /// to `parent`. Default: nothing. Caller is responsible for clearing
    /// `parent` before calling.
    func buildDecorations(into parent: SKNode, size s: CGFloat) {
        let dark = NSColor.black.withAlphaComponent(0.65)

        switch self {
        case .cat:
            let pink = NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.78, alpha: 0.85)
            let whisker = NSColor.black.withAlphaComponent(0.45)

            // Inner ears: smaller pink triangles nested inside the outer ear
            // triangles defined by the body path.
            for sign: CGFloat in [-1, 1] {
                let inner = SKShapeNode()
                let p = CGMutablePath()
                p.move(to: CGPoint(x: sign * s * 0.40, y: s * 0.74))
                p.addLine(to: CGPoint(x: sign * s * 0.30, y: s * 0.97))
                p.addLine(to: CGPoint(x: sign * s * 0.16, y: s * 0.74))
                p.closeSubpath()
                inner.path = p
                inner.fillColor = pink
                inner.strokeColor = .clear
                parent.addChild(inner)
            }

            // Nose: small downward-pointing triangle just above the whiskers.
            let nose = SKShapeNode()
            let np = CGMutablePath()
            np.move(to: CGPoint(x: -s * 0.05, y: s * 0.34))
            np.addLine(to: CGPoint(x:  s * 0.05, y: s * 0.34))
            np.addLine(to: CGPoint(x:  0,        y: s * 0.27))
            np.closeSubpath()
            nose.path = np
            nose.fillColor = dark
            nose.strokeColor = .clear
            parent.addChild(nose)

            // Whiskers: 3 lines per side, slight droop on outer end.
            let whiskerYs: [CGFloat] = [s * 0.32, s * 0.30, s * 0.27]
            let droops:    [CGFloat] = [s * 0.01, 0,         -s * 0.015]
            for sign: CGFloat in [-1, 1] {
                for (y, dy) in zip(whiskerYs, droops) {
                    let line = SKShapeNode()
                    let lp = CGMutablePath()
                    lp.move(to: CGPoint(x: sign * s * 0.10, y: y))
                    lp.addLine(to: CGPoint(x: sign * s * 0.42, y: y + dy))
                    line.path = lp
                    line.strokeColor = whisker
                    line.lineWidth = max(1.0, s * 0.025)
                    line.lineCap = .round
                    parent.addChild(line)
                }
            }

        case .dog:
            // Black nose at the top of the snout area.
            let nose = SKShapeNode(ellipseOf: CGSize(width: s * 0.16, height: s * 0.12))
            nose.position = CGPoint(x: 0, y: s * 0.32)
            nose.fillColor = dark
            nose.strokeColor = .clear
            parent.addChild(nose)
            // Tiny pink tongue dropping from below the nose.
            let tongue = SKShapeNode()
            let tp = CGMutablePath()
            tp.move(to: CGPoint(x: -s * 0.06, y: s * 0.24))
            tp.addQuadCurve(
                to: CGPoint(x: s * 0.06, y: s * 0.24),
                control: CGPoint(x: 0, y: s * 0.10))
            tp.closeSubpath()
            tongue.path = tp
            tongue.fillColor = NSColor(calibratedRed: 0.92, green: 0.18, blue: 0.22, alpha: 1.0)
            tongue.strokeColor = .clear
            parent.addChild(tongue)

        case .owl:
            // Facial disks: large semi-transparent dark circles centered on
            // each eye, framing the white eye whites that render on top.
            let diskColor = NSColor.black.withAlphaComponent(0.20)
            for sign: CGFloat in [-1, 1] {
                let disk = SKShapeNode(circleOfRadius: s * 0.18)
                disk.position = CGPoint(x: sign * s * 0.20, y: s * 0.55)
                disk.fillColor = diskColor
                disk.strokeColor = NSColor.black.withAlphaComponent(0.30)
                disk.lineWidth = 1.0
                parent.addChild(disk)
            }
            // Beak: small downward triangle between the eyes.
            let beak = SKShapeNode()
            let bp = CGMutablePath()
            bp.move(to: CGPoint(x: -s * 0.06, y: s * 0.45))
            bp.addLine(to: CGPoint(x:  s * 0.06, y: s * 0.45))
            bp.addLine(to: CGPoint(x:  0,        y: s * 0.32))
            bp.closeSubpath()
            beak.path = bp
            beak.fillColor = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.20, alpha: 1.0)
            beak.strokeColor = NSColor.black.withAlphaComponent(0.4)
            beak.lineWidth = 0.8
            parent.addChild(beak)

        case .panda:
            let black = NSColor.black.withAlphaComponent(0.85)
            // Two rounded ears popping above the head silhouette.
            for sign: CGFloat in [-1, 1] {
                let ear = SKShapeNode(circleOfRadius: s * 0.18)
                ear.position = CGPoint(x: sign * s * 0.30, y: s * 0.85)
                ear.fillColor = black
                ear.strokeColor = .clear
                parent.addChild(ear)
            }
            // Eye patches: tall ovals tilted slightly inward, framing each eye.
            for sign: CGFloat in [-1, 1] {
                let patch = SKShapeNode(ellipseOf: CGSize(width: s * 0.22, height: s * 0.30))
                patch.position = CGPoint(x: sign * s * 0.20, y: s * 0.55)
                patch.zRotation = sign * 0.20
                patch.fillColor = black
                patch.strokeColor = .clear
                parent.addChild(patch)
            }
            // Nose.
            let nose = SKShapeNode(ellipseOf: CGSize(width: s * 0.14, height: s * 0.10))
            nose.position = CGPoint(x: 0, y: s * 0.32)
            nose.fillColor = black
            nose.strokeColor = .clear
            parent.addChild(nose)
            // Mouth: short connector from nose then a small smile arc below.
            let mouthLine = max(1.2, s * 0.035)
            let connector = SKShapeNode()
            let cpath = CGMutablePath()
            cpath.move(to: CGPoint(x: 0, y: s * 0.27))
            cpath.addLine(to: CGPoint(x: 0, y: s * 0.20))
            connector.path = cpath
            connector.strokeColor = black
            connector.lineWidth = mouthLine
            connector.lineCap = .round
            parent.addChild(connector)
            let smile = SKShapeNode()
            let spath = CGMutablePath()
            spath.move(to: CGPoint(x: -s * 0.08, y: s * 0.20))
            spath.addQuadCurve(
                to: CGPoint(x:  s * 0.08, y: s * 0.20),
                control: CGPoint(x: 0, y: s * 0.12))
            smile.path = spath
            smile.strokeColor = black
            smile.fillColor = .clear
            smile.lineWidth = mouthLine
            smile.lineCap = .round
            parent.addChild(smile)

        case .robot:
            let metalDark = NSColor.black.withAlphaComponent(0.55)

            // Antenna LED bulb on top of the stem.
            let bulb = SKShapeNode(circleOfRadius: s * 0.08)
            bulb.position = CGPoint(x: 0, y: s * 1.06)
            bulb.fillColor = NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.30, alpha: 1.0)
            bulb.strokeColor = NSColor.black.withAlphaComponent(0.5)
            bulb.lineWidth = 1.0
            parent.addChild(bulb)

            // Visor: dark rounded rectangle behind the eyes.
            let visor = SKShapeNode(
                rect: CGRect(x: -s * 0.34, y: s * 0.42, width: s * 0.68, height: s * 0.26),
                cornerRadius: s * 0.05)
            visor.fillColor = NSColor.black.withAlphaComponent(0.55)
            visor.strokeColor = NSColor.black.withAlphaComponent(0.4)
            visor.lineWidth = 1.0
            parent.addChild(visor)

            // Mouth grille: small rectangle with three vertical bars.
            let mouth = SKShapeNode(
                rect: CGRect(x: -s * 0.14, y: s * 0.20, width: s * 0.28, height: s * 0.08),
                cornerRadius: s * 0.015)
            mouth.fillColor = metalDark
            mouth.strokeColor = NSColor.black.withAlphaComponent(0.4)
            mouth.lineWidth = 0.8
            parent.addChild(mouth)
            for i in -1...1 {
                let bar = SKShapeNode()
                let bp = CGMutablePath()
                let x = CGFloat(i) * s * 0.06
                bp.move(to: CGPoint(x: x, y: s * 0.215))
                bp.addLine(to: CGPoint(x: x, y: s * 0.265))
                bar.path = bp
                bar.strokeColor = NSColor.black.withAlphaComponent(0.7)
                bar.lineWidth = max(0.8, s * 0.018)
                parent.addChild(bar)
            }

            // Four bolts at the chassis corners.
            let boltCenters: [CGPoint] = [
                CGPoint(x: -s * 0.40, y: s * 0.10),
                CGPoint(x:  s * 0.40, y: s * 0.10),
                CGPoint(x: -s * 0.40, y: s * 0.75),
                CGPoint(x:  s * 0.40, y: s * 0.75),
            ]
            for c in boltCenters {
                let bolt = SKShapeNode(circleOfRadius: s * 0.04)
                bolt.position = c
                bolt.fillColor = metalDark
                bolt.strokeColor = NSColor.black.withAlphaComponent(0.5)
                bolt.lineWidth = 0.8
                parent.addChild(bolt)
            }

        default:
            break
        }
    }
}
