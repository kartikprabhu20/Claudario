namespace Claudario.Windows.Mascot;

public enum MascotActivity
{
    Idle, Thinking, Reading, Coding, Running,
    Planning, Browsing, DeepThink, Compacting, Dancing
}

public static class MascotActivityExtensions
{
    // Matches macOS MascotActivity.prop
    public static string Prop(this MascotActivity a) => a switch
    {
        MascotActivity.Thinking   => "❓",
        MascotActivity.Reading    => "📖",
        MascotActivity.Coding     => "⌨️",
        MascotActivity.Running    => "⚡",
        MascotActivity.Planning   => "📋",
        MascotActivity.Browsing   => "🌐",
        MascotActivity.DeepThink  => "💭",
        MascotActivity.Compacting => "🌀",
        MascotActivity.Dancing    => "🎉",
        _                         => "",
    };

    // Matches macOS MascotActivity.speedMultiplier
    public static double SpeedMultiplier(this MascotActivity a) => a switch
    {
        MascotActivity.Running    => 1.6,
        MascotActivity.Browsing   => 0.7,
        MascotActivity.DeepThink  => 0.5,
        MascotActivity.Compacting => 0,   // rotation, not walking
        MascotActivity.Dancing    => 0,   // x-jumps, not walking
        _                         => 1.0,
    };

    // Matches macOS MascotActivity.category(forTool:)
    public static MascotActivity CategoryForTool(string toolName) => toolName switch
    {
        "Read" or "Grep" or "Glob" or "NotebookRead"           => MascotActivity.Reading,
        "Edit" or "Write" or "MultiEdit" or "NotebookEdit"     => MascotActivity.Coding,
        "Bash" or "BashOutput" or "KillShell"                  => MascotActivity.Running,
        "WebFetch" or "WebSearch"                              => MascotActivity.Browsing,
        "TodoWrite" or "ExitPlanMode"                          => MascotActivity.Planning,
        "Task"                                                 => MascotActivity.DeepThink,
        _                                                      => MascotActivity.Thinking,
    };
}
