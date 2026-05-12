using System.Text;
using System.Windows;
using Application = System.Windows.Application;
using Microsoft.Win32;
using Claudario.Windows.Audio;
using Claudario.Windows.Install;
using Claudario.Windows.Mascot;
using Claudario.Windows.Overlay;
using Claudario.Windows.Server;
using Claudario.Windows.Settings;
using WinForms = System.Windows.Forms;

namespace Claudario.Windows;

public partial class App : Application
{
    private WinForms.NotifyIcon? _tray;
    private OverlayWindow?       _overlay;
    private EventServer?         _server;
    private EventRouter?         _router;
    private bool _enabled = true;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var settings = new MascotSettings();
        _overlay = new OverlayWindow(settings);
        _overlay.Show();

        StartServer();
        BuildTray();
    }

    // ── Server ────────────────────────────────────────────────────────────────

    private void StartServer()
    {
        _router = new EventRouter();

        _router.OnWalk = () =>
            _overlay?.Scene.SetState(MascotState.Walking);

        _router.OnIdle = () =>
            _overlay?.Scene.SetState(MascotState.Idle);

        _router.OnCelebrate = () =>
        {
            _overlay?.Scene.Celebrate();
            SoundPlayer.PlayCelebrate();
        };

        _router.OnNotify = () =>
        {
            _overlay?.Scene.Notify();
            SoundPlayer.PlayNotify();
        };

        _router.OnActivity = activity =>
            _overlay?.Scene.SetActivity(activity);

        _server = new EventServer(_router);
        _server.Start(port =>
            System.Diagnostics.Debug.WriteLine($"Claudario: listening on port {port}"));
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    protected override void OnExit(ExitEventArgs e)
    {
        _server?.Dispose();
        if (_tray != null) { _tray.Visible = false; _tray.Dispose(); }
        base.OnExit(e);
    }

    // ── Tray icon ─────────────────────────────────────────────────────────────

    private void BuildTray()
    {
        var menu = new WinForms.ContextMenuStrip();
        // Rebuild items each time the menu opens so checkmarks reflect current state
        menu.Opening += (_, _) => { menu.Items.Clear(); FillTrayMenu(menu); };
        FillTrayMenu(menu);

        _tray = new WinForms.NotifyIcon
        {
            Icon            = CreateTrayIcon(),
            Text            = "Claudario",
            Visible         = true,
            ContextMenuStrip = menu,
        };
    }

    private void FillTrayMenu(WinForms.ContextMenuStrip menu)
    {
        Add(menu, "Enabled",          ToggleEnabled,          check: _enabled);
        Add(menu, "Launch at Login",  ToggleLaunchAtLogin,    check: IsLaunchAtLogin());
        menu.Items.Add(new WinForms.ToolStripSeparator());
        Add(menu, "Install Claude Code Hooks",   InstallHooks);
        Add(menu, "Uninstall Claude Code Hooks", UninstallHooks);
        menu.Items.Add(new WinForms.ToolStripSeparator());
        Add(menu, "Test: Walk + Jump", TestWalkJump);
        Add(menu, "Test: Notify",      TestNotify);
        menu.Items.Add(new WinForms.ToolStripSeparator());
        Add(menu, "Show Controls…",   ShowControls);
        menu.Items.Add(new WinForms.ToolStripSeparator());
        Add(menu, "Quit",             () => Shutdown());
    }

    private static void Add(WinForms.ContextMenuStrip menu, string text,
                             Action onClick, bool? check = null)
    {
        var item = new WinForms.ToolStripMenuItem(text) { Checked = check ?? false };
        item.Click += (_, _) => onClick();
        menu.Items.Add(item);
    }

    // ── Enabled / disabled ────────────────────────────────────────────────────

    private void ToggleEnabled()
    {
        _enabled = !_enabled;
        if (_enabled) _overlay?.Show();
        else          _overlay?.Hide();
    }

    // ── Launch at Login ───────────────────────────────────────────────────────

    private const string RunKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";

    private static bool IsLaunchAtLogin()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue("Claudario") != null;
    }

    private static void ToggleLaunchAtLogin()
    {
        if (IsLaunchAtLogin())
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            key?.DeleteValue("Claudario", throwOnMissingValue: false);
        }
        else
        {
            string? exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe)) return;
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            key?.SetValue("Claudario", $"\"{exe}\"", RegistryValueKind.String);
        }
    }

    // ── Hook install / uninstall ──────────────────────────────────────────────

    private static void InstallHooks()
    {
        try
        {
            string path = new HookInstaller().Install();
            WinForms.MessageBox.Show(
                $"Hooks installed.\n\nPatched: {path}\n\nClaude Code will now notify Claudario.",
                "Claudario", WinForms.MessageBoxButtons.OK, WinForms.MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            WinForms.MessageBox.Show(
                $"Hook install failed:\n{ex.Message}",
                "Claudario", WinForms.MessageBoxButtons.OK, WinForms.MessageBoxIcon.Warning);
        }
    }

    private static void UninstallHooks()
    {
        try
        {
            new HookInstaller().Uninstall();
            WinForms.MessageBox.Show(
                "Hooks removed.\n\nClaude Code will no longer notify Claudario.",
                "Claudario", WinForms.MessageBoxButtons.OK, WinForms.MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            WinForms.MessageBox.Show(
                $"Hook uninstall failed:\n{ex.Message}",
                "Claudario", WinForms.MessageBoxButtons.OK, WinForms.MessageBoxIcon.Warning);
        }
    }

    // ── Test events ───────────────────────────────────────────────────────────

    private void TestWalkJump()
    {
        Send("""{"hook_event_name":"UserPromptSubmit","session_id":"menubar-test"}""");
        Task.Delay(4000).ContinueWith(_ =>
            Dispatcher.Invoke(() =>
                Send("""{"hook_event_name":"Stop","session_id":"menubar-test"}""")));
    }

    private void TestNotify() =>
        Send("""{"hook_event_name":"Notification","session_id":"menubar-test"}""");

    private void Send(string json) =>
        _router?.Handle(Encoding.UTF8.GetBytes(json));

    // ── Controls dialog ───────────────────────────────────────────────────────

    private static void ShowControls()
    {
        WinForms.MessageBox.Show(
            "Click the mascot to take control. While in control:\n\n" +
            "  ← →    Walk left / right\n" +
            "  ↑      Jump\n" +
            "  G      Start dino runner game\n" +
            "  Esc    Release control\n\n" +
            "Activities (press key while in control):\n" +
            "  1 Idle        6 Planning\n" +
            "  2 Thinking    7 Browsing\n" +
            "  3 Reading     8 Deep think\n" +
            "  4 Coding      9 Compacting\n" +
            "  5 Running     0 Dancing\n\n" +
            "Size:     ,  /  .\n" +
            "Color:    C   (10 colors)\n" +
            "Variant:  V   (7 shapes)\n\n" +
            "Petting:  wag cursor over mascot head\n\n" +
            "In dino game:\n" +
            "  ↑ / Space   Jump\n" +
            "  R           Restart\n" +
            "  Esc         Exit game",
            "Claudario Controls",
            WinForms.MessageBoxButtons.OK,
            WinForms.MessageBoxIcon.None);
    }

    // ── Tray icon bitmap ──────────────────────────────────────────────────────

    private static System.Drawing.Icon CreateTrayIcon()
    {
        const int size = 16;
        using var bmp = new System.Drawing.Bitmap(size, size,
            System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var g = System.Drawing.Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.Clear(System.Drawing.Color.Transparent);

        using var brush = new System.Drawing.SolidBrush(
            System.Drawing.Color.FromArgb(255, 230, 120, 50));
        g.FillEllipse(brush, 1, 1, size - 2, size - 2);

        using var eyeBrush   = new System.Drawing.SolidBrush(System.Drawing.Color.White);
        using var pupilBrush = new System.Drawing.SolidBrush(System.Drawing.Color.Black);
        g.FillEllipse(eyeBrush,   4, 5, 3, 3);
        g.FillEllipse(eyeBrush,   9, 5, 3, 3);
        g.FillEllipse(pupilBrush, 5, 6, 2, 2);
        g.FillEllipse(pupilBrush, 10, 6, 2, 2);

        return System.Drawing.Icon.FromHandle(bmp.GetHicon());
    }
}
