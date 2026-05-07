import AppKit

enum DockOrientation: String {
    case bottom, left, right
}

struct DockInfo {
    var orientation: DockOrientation
    var autohide: Bool
    var rect: NSRect
    var screen: NSScreen
}

enum DockGeometry {
    static let fallbackStripHeight: CGFloat = 80
    /// We give the overlay extra headroom above the Dock so jumps and
    /// tall activity props (like the 🌀 prop above the mascot's head)
    /// aren't clipped. Final strip height = Dock height × this.
    static let heightMultiplier: CGFloat = 2

    static func current() -> DockInfo {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let orientation: DockOrientation = {
            if let raw = CFPreferencesCopyAppValue("orientation" as CFString,
                                                   "com.apple.dock" as CFString) as? String,
               let o = DockOrientation(rawValue: raw) {
                return o
            }
            return .bottom
        }()
        let autohide: Bool = {
            if let n = CFPreferencesCopyAppValue("autohide" as CFString,
                                                 "com.apple.dock" as CFString) as? NSNumber {
                return n.boolValue
            }
            return false
        }()

        let full = screen.frame
        let visible = screen.visibleFrame

        let baseHeight: CGFloat
        switch orientation {
        case .bottom:
            let dockHeight = max(0, visible.minY - full.minY)
            baseHeight = dockHeight > 0 ? dockHeight : fallbackStripHeight
        case .left, .right:
            baseHeight = fallbackStripHeight
        }
        let stripHeight = baseHeight * heightMultiplier
        let rect = NSRect(x: full.minX, y: full.minY, width: full.width, height: stripHeight)

        return DockInfo(orientation: orientation, autohide: autohide, rect: rect, screen: screen)
    }
}
