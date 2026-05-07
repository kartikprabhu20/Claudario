import CoreGraphics

enum MascotVariant: Int, CaseIterable {
    case classic, round, tall, egg, bean

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .round:   return "Round"
        case .tall:    return "Tall"
        case .egg:     return "Egg"
        case .bean:    return "Bean"
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

        case .round:
            return CGPath(
                ellipseIn: CGRect(x: -s / 2, y: 0, width: s, height: s),
                transform: nil)

        case .tall:
            let w = s * 0.78
            let h = s * 1.05
            return CGPath(
                roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: h),
                cornerWidth: w * 0.5, cornerHeight: w * 0.5, transform: nil)

        case .bean:
            let w = s * 1.10
            let h = s * 0.78
            return CGPath(
                roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: h),
                cornerWidth: h * 0.5, cornerHeight: h * 0.5, transform: nil)

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
        }
    }

    /// Eye-center Y, relative to the body's bottom (y=0).
    func eyeY(size s: CGFloat) -> CGFloat {
        switch self {
        case .classic: return s * 0.70
        case .round:   return s * 0.65
        case .tall:    return s * 0.78
        case .egg:     return s * 0.62
        case .bean:    return s * 0.50
        }
    }

    /// Vertical offset for foot attachment (y=0 = body's bottom edge).
    func footY(size _: CGFloat) -> CGFloat { 0 }
}
