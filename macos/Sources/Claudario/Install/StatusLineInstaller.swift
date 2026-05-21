import Foundation

enum StatusLineInstallerError: LocalizedError {
    case scriptMissing
    case settingsCorrupt(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptMissing:
            return "Bundled statusline script missing from app resources."
        case .settingsCorrupt(let msg):
            return "~/.claude/settings.json is not valid JSON: \(msg)"
        case .writeFailed(let msg):
            return "Failed to write settings: \(msg)"
        }
    }
}

/// Installs Claudario's statusline wrapper so the mascot can read the
/// `context_window` and `rate_limits` fields Claude Code only exposes to
/// the statusline pipeline. If the user already had a statusline configured,
/// its command is preserved in ~/.claudario/upstream-statusline.cmd and the
/// wrapper forwards stdin to it so their original output still renders.
final class StatusLineInstaller {
    private static let marker = "/.claudario/statusline"

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var configDir: URL { home.appendingPathComponent(".claudario") }
    private var scriptDest: URL { configDir.appendingPathComponent("statusline") }
    private var upstreamCmdFile: URL { configDir.appendingPathComponent("upstream-statusline.cmd") }
    private var claudeDir: URL { home.appendingPathComponent(".claude") }
    private var settingsPath: URL { claudeDir.appendingPathComponent("settings.json") }

    var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: settingsPath.path),
              let data = try? Data(contentsOf: settingsPath),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }
        return Self.commandString(from: json)?.contains(Self.marker) == true
    }

    @discardableResult
    func install() throws -> URL {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try copyBundledScript()

        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsPath.path) {
            let data = try Data(contentsOf: settingsPath)
            let backup = settingsPath
                .deletingPathExtension()
                .appendingPathExtension("json.bak.\(Int(Date().timeIntervalSince1970))")
            try data.write(to: backup)
            do {
                if let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    json = parsed
                }
            } catch {
                throw StatusLineInstallerError.settingsCorrupt(error.localizedDescription)
            }
        }

        // Preserve any existing non-Claudario statusline so we can forward
        // stdin to it (and restore it on uninstall).
        if let existing = Self.commandString(from: json), !existing.contains(Self.marker) {
            try existing.write(to: upstreamCmdFile, atomically: true, encoding: .utf8)
        }

        json["statusLine"] = [
            "type": "command",
            "command": "bash \(scriptDest.path)",
        ]

        do {
            let out = try JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: settingsPath)
        } catch {
            throw StatusLineInstallerError.writeFailed(error.localizedDescription)
        }
        return settingsPath
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else { return }
        let data = try Data(contentsOf: settingsPath)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Only touch statusLine if it's currently Claudario's.
        if let current = Self.commandString(from: json), current.contains(Self.marker) {
            if let upstream = try? String(contentsOf: upstreamCmdFile, encoding: .utf8) {
                let trimmed = upstream.trimmingCharacters(in: .whitespacesAndNewlines)
                json["statusLine"] = ["type": "command", "command": trimmed]
            } else {
                json.removeValue(forKey: "statusLine")
            }
        }

        try? FileManager.default.removeItem(at: upstreamCmdFile)

        let out = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: settingsPath)
    }

    private func copyBundledScript() throws {
        guard let bundled = Bundle.main.url(forResource: "claudario-statusline", withExtension: nil) else {
            throw StatusLineInstallerError.scriptMissing
        }
        if FileManager.default.fileExists(atPath: scriptDest.path) {
            try FileManager.default.removeItem(at: scriptDest)
        }
        try FileManager.default.copyItem(at: bundled, to: scriptDest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptDest.path)
    }

    private static func commandString(from json: [String: Any]) -> String? {
        (json["statusLine"] as? [String: Any])?["command"] as? String
    }
}
