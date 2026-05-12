import AppKit

struct MascotColor {
    let name: String
    let body: NSColor
    let foot: NSColor
}

enum MascotPalette {
    static let colors: [MascotColor] = [
        MascotColor(
            name: "Anthropic Orange",
            body: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.45, green: 0.22, blue: 0.08, alpha: 1.0)),
        MascotColor(
            name: "Sky Blue",
            body: NSColor(calibratedRed: 0.40, green: 0.65, blue: 0.90, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.50, alpha: 1.0)),
        MascotColor(
            name: "Mint",
            body: NSColor(calibratedRed: 0.45, green: 0.80, blue: 0.55, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.25, alpha: 1.0)),
        MascotColor(
            name: "Lavender",
            body: NSColor(calibratedRed: 0.65, green: 0.55, blue: 0.85, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.30, green: 0.22, blue: 0.45, alpha: 1.0)),
        MascotColor(
            name: "Coral",
            body: NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.45, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.50, green: 0.18, blue: 0.18, alpha: 1.0)),
        MascotColor(
            name: "Mustard",
            body: NSColor(calibratedRed: 0.90, green: 0.75, blue: 0.30, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.10, alpha: 1.0)),
        MascotColor(
            name: "Rose",
            body: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.70, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.50, green: 0.22, blue: 0.32, alpha: 1.0)),
        MascotColor(
            name: "Teal",
            body: NSColor(calibratedRed: 0.30, green: 0.70, blue: 0.70, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.35, alpha: 1.0)),
        MascotColor(
            name: "Cocoa",
            body: NSColor(calibratedRed: 0.65, green: 0.45, blue: 0.30, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.10, alpha: 1.0)),
        MascotColor(
            name: "Slate",
            body: NSColor(calibratedRed: 0.55, green: 0.60, blue: 0.65, alpha: 1.0),
            foot: NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.35, alpha: 1.0)),
    ]
}
