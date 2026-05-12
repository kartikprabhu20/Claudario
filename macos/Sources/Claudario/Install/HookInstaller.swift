import Foundation

enum HookInstallerError: LocalizedError {
    case hookScriptMissing
    case settingsCorrupt(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .hookScriptMissing:
            return "Bundled hook script missing from app resources."
        case .settingsCorrupt(let msg):
            return "~/.claude/settings.json is not valid JSON: \(msg)"
        case .writeFailed(let msg):
            return "Failed to write settings: \(msg)"
        }
    }
}

final class HookInstaller {
    private static let hookEvents = [
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SubagentStop",
        "Notification",
        "SessionStart",
        "SessionEnd",
        "PreCompact",
    ]
    private static let marker = "/.claudario/"

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var configDir: URL { home.appendingPathComponent(".claudario") }
    private var hookDest: URL { configDir.appendingPathComponent("hook") }
    private var claudeDir: URL { home.appendingPathComponent(".claude") }
    private var settingsPath: URL { claudeDir.appendingPathComponent("settings.json") }

    @discardableResult
    func install() throws -> URL {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try copyBundledHook()

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
                throw HookInstallerError.settingsCorrupt(error.localizedDescription)
            }
        }

        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let entry: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": hookDest.path]],
        ]
        for event in Self.hookEvents {
            var arr = (hooks[event] as? [[String: Any]]) ?? []
            arr.removeAll { Self.entryIsClaudario($0) }
            arr.append(entry)
            hooks[event] = arr
        }
        json["hooks"] = hooks

        do {
            let out = try JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: settingsPath)
        } catch {
            throw HookInstallerError.writeFailed(error.localizedDescription)
        }
        return settingsPath
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else { return }
        let data = try Data(contentsOf: settingsPath)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var arr = value as? [[String: Any]] else { continue }
            arr.removeAll { Self.entryIsClaudario($0) }
            if arr.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = arr
            }
        }
        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }
        let out = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: settingsPath)
    }

    private func copyBundledHook() throws {
        guard let bundled = Bundle.main.url(forResource: "claudario-hook", withExtension: nil) else {
            throw HookInstallerError.hookScriptMissing
        }
        if FileManager.default.fileExists(atPath: hookDest.path) {
            try FileManager.default.removeItem(at: hookDest)
        }
        try FileManager.default.copyItem(at: bundled, to: hookDest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookDest.path)
    }

    private static func entryIsClaudario(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(Self.marker) == true }
    }
}
