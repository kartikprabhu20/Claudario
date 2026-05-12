using System.Text.Json;
using Claudario.Windows.Mascot;

namespace Claudario.Windows.Server;

public sealed class EventRouter
{
    public Action? OnWalk      { get; set; }
    public Action? OnIdle      { get; set; }
    public Action? OnCelebrate { get; set; }
    public Action? OnNotify    { get; set; }
    public Action<MascotActivity>? OnActivity { get; set; }

    private struct SessionState
    {
        public bool           IsWalking;
        public MascotActivity Activity;
        public DateTime       LastSeen;
    }

    private readonly Dictionary<string, SessionState> _sessions = new();
    private readonly object _lock        = new();
    private string?         _lastActiveSessionId;
    private MascotActivity  _lastEmitted = MascotActivity.Idle;
    private static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(5);

    public void Handle(byte[] json)
    {
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); }
        catch { return; }

        using (doc)
        {
            var root = doc.RootElement;
            string eventName = root.TryGetProperty("hook_event_name", out var en) ? en.GetString() ?? "" : "";
            string sessionId = root.TryGetProperty("session_id",       out var si) ? si.GetString() ?? "default" : "default";
            string? toolName = root.TryGetProperty("tool_name",        out var tn) ? tn.GetString() : null;

            Process(eventName, sessionId, toolName);
        }
    }

    private void Process(string eventName, string sessionId, string? toolName)
    {
        lock (_lock)
        {
            EvictStale();

            var now  = DateTime.UtcNow;
            var sess = _sessions.TryGetValue(sessionId, out var s) ? s
                     : new SessionState { IsWalking = false, Activity = MascotActivity.Idle, LastSeen = now };
            sess.LastSeen = now;
            _lastActiveSessionId = sessionId;

            switch (eventName)
            {
                case "SessionStart":
                    sess.IsWalking = false;
                    sess.Activity  = MascotActivity.Idle;
                    break;

                case "UserPromptSubmit":
                {
                    bool wasWalking = AnyWalking();
                    sess.IsWalking = true;
                    sess.Activity  = MascotActivity.Thinking;
                    _sessions[sessionId] = sess;
                    if (!wasWalking) FireOnMain(OnWalk);
                    EmitActivity();
                    return;
                }

                case "PreToolUse":
                {
                    bool wasWalking = AnyWalking();
                    sess.IsWalking = true;
                    sess.Activity  = MascotActivityExtensions.CategoryForTool(toolName ?? "");
                    _sessions[sessionId] = sess;
                    if (!wasWalking) FireOnMain(OnWalk);
                    EmitActivity();
                    return;
                }

                case "PostToolUse":
                    sess.Activity = MascotActivity.Thinking;
                    _sessions[sessionId] = sess;
                    EmitActivity();
                    return;

                case "PreCompact":
                    sess.IsWalking = true;
                    sess.Activity  = MascotActivity.Compacting;
                    _sessions[sessionId] = sess;
                    FireOnMain(OnWalk);
                    EmitActivity();
                    return;

                case "Notification" or "PermissionRequest":
                    FireOnMain(OnNotify);
                    break;

                case "Stop" or "SubagentStop":
                    sess.IsWalking = false;
                    sess.Activity  = MascotActivity.Idle;
                    _sessions[sessionId] = sess;
                    if (!AnyWalking())
                    {
                        FireOnMain(OnIdle);
                        FireOnMain(OnCelebrate);
                        EmitIdleActivity();
                    }
                    else
                    {
                        EmitActivity();
                    }
                    return;

                case "SessionEnd":
                    _sessions.Remove(sessionId);
                    if (!AnyWalking())
                    {
                        FireOnMain(OnIdle);
                        EmitIdleActivity();
                    }
                    else
                    {
                        EmitActivity();
                    }
                    return;
            }

            _sessions[sessionId] = sess;
        }
    }

    private void EmitActivity()
    {
        MascotActivity activity;
        if (_lastActiveSessionId is not null &&
            _sessions.TryGetValue(_lastActiveSessionId, out var ls) && ls.IsWalking)
            activity = ls.Activity;
        else if (_sessions.Values.FirstOrDefault(x => x.IsWalking) is { IsWalking: true } w)
            activity = w.Activity;
        else
            activity = MascotActivity.Idle;

        if (activity == _lastEmitted) return;
        _lastEmitted = activity;
        var act = activity;
        FireOnMain(() => OnActivity?.Invoke(act));
    }

    private void EmitIdleActivity()
    {
        if (_lastEmitted == MascotActivity.Idle) return;
        _lastEmitted = MascotActivity.Idle;
        FireOnMain(() => OnActivity?.Invoke(MascotActivity.Idle));
    }

    private bool AnyWalking() => _sessions.Values.Any(s => s.IsWalking);

    private void EvictStale()
    {
        var cutoff = DateTime.UtcNow - StaleAfter;
        foreach (var key in _sessions.Keys.ToList())
            if (_sessions[key].LastSeen < cutoff)
                _sessions.Remove(key);
    }

    public void Reset()
    {
        bool needsIdleEmit;
        lock (_lock)
        {
            _sessions.Clear();
            _lastActiveSessionId = null;
            needsIdleEmit = _lastEmitted != MascotActivity.Idle;
            _lastEmitted  = MascotActivity.Idle;
        }
        FireOnMain(OnIdle);
        if (needsIdleEmit) FireOnMain(() => OnActivity?.Invoke(MascotActivity.Idle));
    }

    private static void FireOnMain(Action? action)
    {
        if (action is null) return;
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(action);
    }
}
