using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Claudario.Windows.Install;

/// <summary>
/// Installs / uninstalls the Claudario hook entries in
/// %USERPROFILE%\.claude\settings.json.  Matches the macOS HookInstaller
/// port 1-to-1 in behaviour; uses System.Text.Json.Nodes for mutable JSON.
/// </summary>
public sealed class HookInstaller
{
    private static readonly string[] HookEvents =
    [
        "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "Stop", "SubagentStop", "Notification",
        "SessionStart", "SessionEnd", "PreCompact",
    ];

    // Substring present in any command we wrote — used to identify our entries.
    private const string Marker = ".claudario";

    private string Home        => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    private string ConfigDir   => Path.Combine(Home, ".claudario");
    private string HookDest    => Path.Combine(ConfigDir, "hook.cmd");
    private string ClaudeDir   => Path.Combine(Home, ".claude");
    private string SettingsPath => Path.Combine(ClaudeDir, "settings.json");

    // ── Install ───────────────────────────────────────────────────────────────

    public string Install()
    {
        Directory.CreateDirectory(ConfigDir);
        CopyBundledHook();

        Directory.CreateDirectory(ClaudeDir);

        JsonObject root = ReadOrCreateSettings();

        // Backup before modifying
        if (File.Exists(SettingsPath))
        {
            string bak = SettingsPath + $".bak.{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
            File.Copy(SettingsPath, bak, overwrite: true);
        }

        var hooksObj = root["hooks"]?.AsObject() ?? new JsonObject();
        root["hooks"] = hooksObj;

        // Command: invoke hook.cmd via cmd.exe so Claude Code needn't know about .cmd
        string cmd = $"cmd.exe /c \"{HookDest}\"";
        var entry = new JsonObject
        {
            ["matcher"] = "*",
            ["hooks"]   = new JsonArray
            {
                new JsonObject { ["type"] = "command", ["command"] = cmd }
            },
        };

        foreach (string ev in HookEvents)
        {
            var arr = hooksObj[ev]?.AsArray() ?? new JsonArray();
            // Remove any existing Claudario entries then append the fresh one
            for (int i = arr.Count - 1; i >= 0; i--)
                if (EntryIsClaudario(arr[i]?.AsObject())) arr.RemoveAt(i);
            arr.Add(entry.DeepClone());
            hooksObj[ev] = arr;
        }

        WriteSettings(root);
        return SettingsPath;
    }

    // ── Uninstall ─────────────────────────────────────────────────────────────

    public void Uninstall()
    {
        if (!File.Exists(SettingsPath)) return;
        JsonObject root = ReadOrCreateSettings();
        if (root["hooks"] is not JsonObject hooksObj) return;

        foreach (string ev in HookEvents)
        {
            if (hooksObj[ev] is not JsonArray arr) continue;
            for (int i = arr.Count - 1; i >= 0; i--)
                if (EntryIsClaudario(arr[i]?.AsObject())) arr.RemoveAt(i);
            if (arr.Count == 0) hooksObj.Remove(ev);
        }
        if (hooksObj.Count == 0) root.Remove("hooks");

        WriteSettings(root);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private void CopyBundledHook()
    {
        // Look next to the exe, or fall back to the working directory
        string src = Path.Combine(AppContext.BaseDirectory, "claudario-hook.cmd");
        if (!File.Exists(src))
            throw new FileNotFoundException(
                "claudario-hook.cmd not found next to the executable.", src);

        File.Copy(src, HookDest, overwrite: true);
    }

    private JsonObject ReadOrCreateSettings()
    {
        if (!File.Exists(SettingsPath)) return new JsonObject();
        try
        {
            var node = JsonNode.Parse(File.ReadAllText(SettingsPath));
            return node?.AsObject() ?? new JsonObject();
        }
        catch (JsonException ex)
        {
            throw new InvalidOperationException(
                $"~/.claude/settings.json is not valid JSON: {ex.Message}", ex);
        }
    }

    private void WriteSettings(JsonObject root)
    {
        var opts = new JsonSerializerOptions { WriteIndented = true };
        File.WriteAllText(SettingsPath, root.ToJsonString(opts));
    }

    private static bool EntryIsClaudario(JsonObject? entry)
    {
        if (entry?["hooks"] is not JsonArray inner) return false;
        foreach (var h in inner)
            if (h?["command"]?.GetValue<string>()?.Contains(Marker) == true) return true;
        return false;
    }
}
