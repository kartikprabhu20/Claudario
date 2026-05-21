import AppKit

// Build-time iconset export: render the orange dog mascot at the 10
// standard iconset sizes into <dir>, then exit before the app launches.
// Invoked by build.sh; the resulting .iconset is fed to `iconutil`.
if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--export-iconset" {
    _ = NSApplication.shared
    let outputDir = URL(fileURLWithPath: CommandLine.arguments[2])
    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let entries: [(CGFloat, String)] = [
        (16,   "icon_16x16.png"),
        (32,   "icon_16x16@2x.png"),
        (32,   "icon_32x32.png"),
        (64,   "icon_32x32@2x.png"),
        (128,  "icon_128x128.png"),
        (256,  "icon_128x128@2x.png"),
        (256,  "icon_256x256.png"),
        (512,  "icon_256x256@2x.png"),
        (512,  "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for (px, name) in entries {
        guard let cg = MascotIconRenderer.renderAppIconCGImage(
            variant: .dog,
            color: MascotPalette.colors[0],
            pixelSize: px)
        else {
            FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to encode \(name)\n".utf8))
            exit(1)
        }
        try? data.write(to: outputDir.appendingPathComponent(name))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
