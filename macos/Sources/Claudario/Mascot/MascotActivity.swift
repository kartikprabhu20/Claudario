import Foundation

enum MascotActivity: String, CaseIterable {
    case idle
    case thinking
    case reading
    case coding
    case running
    case planning
    case browsing
    case deepThink
    case compacting
    case dancing

    /// Emoji shown above the mascot's head while this activity is active.
    /// Empty string = no prop.
    var prop: String {
        switch self {
        case .idle:       return ""
        case .thinking:   return "❓"
        case .reading:    return "📖"
        case .coding:     return "⌨️"
        case .running:    return "⚡"
        case .planning:   return "📋"
        case .browsing:   return "🌐"
        case .deepThink:  return "💭"
        case .compacting: return "🌀"
        case .dancing:    return "🎉"
        }
    }

    /// Multiplier applied to base walkSpeed when state is .walking.
    var speedMultiplier: CGFloat {
        switch self {
        case .running:   return 1.6
        case .browsing:  return 0.7
        case .deepThink: return 0.5
        case .compacting: return 0  // motion handled separately (rotate)
        case .dancing:   return 0   // x-jumps, not walking
        default:         return 1.0
        }
    }

    /// Maps a Claude Code tool_name to the activity category. Returns
    /// `.thinking` for unknown / future tools.
    static func category(forTool name: String) -> MascotActivity {
        switch name {
        case "Read", "Grep", "Glob", "NotebookRead":
            return .reading
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return .coding
        case "Bash", "BashOutput", "KillShell":
            return .running
        case "WebFetch", "WebSearch":
            return .browsing
        case "TodoWrite", "ExitPlanMode":
            return .planning
        case "Task":
            return .deepThink
        default:
            return .thinking
        }
    }
}
