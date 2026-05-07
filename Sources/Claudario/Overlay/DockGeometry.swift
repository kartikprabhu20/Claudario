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

        let rect: NSRect
        switch orientation {
        case .bottom:
            let height = max(0, visible.minY - full.minY)
            if height > 0 {
                rect = NSRect(x: full.minX, y: full.minY, width: full.width, height: height)
            } else {
                rect = NSRect(x: full.minX, y: full.minY, width: full.width, height: fallbackStripHeight)
            }
        case .left, .right:
            rect = NSRect(x: full.minX, y: full.minY, width: full.width, height: fallbackStripHeight)
        }

        return DockInfo(orientation: orientation, autohide: autohide, rect: rect, screen: screen)
    }
}
