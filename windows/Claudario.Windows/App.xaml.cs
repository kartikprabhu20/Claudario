using System.Text;
using System.Windows;
using Application = System.Windows.Application;
using Microsoft.Win32;
using SkiaSharp;
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
    private MascotSettings?      _settings;
    private bool _enabled = true;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _settings = new MascotSettings();
        _settings.AppearanceChanged += UpdateTrayIcon;
        _overlay = new OverlayWindow(_settings);
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
            Icon             = CreateTrayIcon(_settings!),
            Text             = "Claudario",
            Visible          = true,
            ContextMenuStrip = menu,
        };
    }

    private void UpdateTrayIcon()
    {
        if (_tray == null || _settings == null) return;
        var old = _tray.Icon;
        _tray.Icon = CreateTrayIcon(_settings);
        old?.Dispose();
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
    // Renders the currently-selected mascot silhouette (body path + variant extras)
    // in the current palette color at 32×32 so high-DPI trays look sharp.

    private static System.Drawing.Icon CreateTrayIcon(MascotSettings settings)
    {
        const int size = 32;
        var variant = (MascotVariant)settings.VariantIndex;
        var palette = MascotPalette.Colors[settings.ColorIndex];

        using var skiaBmp    = new SKBitmap(size, size, SKColorType.Bgra8888, SKAlphaType.Premul);
        using var skiaCanvas = new SKCanvas(skiaBmp);
        skiaCanvas.Clear(SKColors.Transparent);

        // Bounding box extents in mascot-local units (multiples of s).
        // BodyPath coordinates: X ∈ [−widthFactor/2·s, +widthFactor/2·s], Y ∈ [0, heightFactor·s].
        float widthUnits = variant switch
        {
            MascotVariant.Dog => 1.52f,   // floppy ears reach ±0.74 s
            MascotVariant.Owl => 1.14f,   // body widens to ±0.55 s
            _                 => 1.04f,
        };
        float heightUnits = variant switch
        {
            MascotVariant.Cat   => 1.10f,  // ear tips at 1.05 s
            MascotVariant.Owl   => 1.10f,  // tuft tips at 1.05 s
            MascotVariant.Panda => 1.08f,  // ear tops at ~1.03 s (0.85 s centre + 0.18 s radius)
            MascotVariant.Robot => 1.18f,  // antenna bulb top at ~1.14 s (1.06 + 0.08)
            _                   => 1.04f,
        };

        float pad   = size * 0.05f;
        float avail = size - 2 * pad;
        float s     = Math.Min(avail / widthUnits, avail / heightUnits);

        float bodyH = s * heightUnits;

        // Place the bounding box centred in the icon.
        float originX = size / 2f;
        float originY = (size + bodyH) / 2f;  // canvas Y where mascot Y=0 (bottom) sits

        skiaCanvas.Save();
        skiaCanvas.Translate(originX, originY);
        skiaCanvas.Scale(1f, -1f);  // mascot space is Y-up; canvas is Y-down

        using (var bodyPath = variant.BodyPath(s))
        {
            using var fill = new SKPaint { Color = palette.Body, IsAntialias = true };
            skiaCanvas.DrawPath(bodyPath, fill);

            using var stroke = new SKPaint
            {
                Color       = new SKColor(0, 0, 0, 100),
                IsAntialias = true,
                Style       = SKPaintStyle.Stroke,
                StrokeWidth = Math.Max(0.8f, s * 0.04f),
            };
            skiaCanvas.DrawPath(bodyPath, stroke);
        }

        // Panda ears are decorations, not part of BodyPath — add them so the silhouette is distinct.
        if (variant == MascotVariant.Panda)
        {
            using var earPaint = new SKPaint { Color = new SKColor(0, 0, 0, 217), IsAntialias = true };
            foreach (float sign in new[] { -1f, 1f })
                skiaCanvas.DrawCircle(sign * s * 0.30f, s * 0.85f, s * 0.18f, earPaint);
        }

        // Robot antenna bulb is a decoration — the red dot makes the silhouette instantly readable.
        if (variant == MascotVariant.Robot)
        {
            using var bulbPaint = new SKPaint { Color = new SKColor(255, 64, 77, 255), IsAntialias = true };
            skiaCanvas.DrawCircle(0f, s * 1.06f, s * 0.08f, bulbPaint);
        }

        skiaCanvas.Restore();

        return SkiaBitmapToIcon(skiaBmp, size);
    }

    // Wraps the SkiaSharp bitmap in a minimal .ico container (PNG-in-ICO, Vista+ format).
    // This is more reliable than GetHicon() which silently drops 32-bit alpha on Windows 11.
    private static System.Drawing.Icon SkiaBitmapToIcon(SKBitmap skiaBmp, int size)
    {
        using var image   = SKImage.FromBitmap(skiaBmp);
        using var encoded = image.Encode(SKEncodedImageFormat.Png, 100);
        byte[] png = encoded.ToArray();

        using var ms = new System.IO.MemoryStream();
        using var bw = new System.IO.BinaryWriter(ms);

        // ICONDIR
        bw.Write((short)0);   // reserved
        bw.Write((short)1);   // type = icon
        bw.Write((short)1);   // image count

        // ICONDIRENTRY
        byte dim = (byte)(size <= 255 ? size : 0);
        bw.Write(dim);           // width  (0 = 256)
        bw.Write(dim);           // height
        bw.Write((byte)0);       // color count (0 = > 8bpp)
        bw.Write((byte)0);       // reserved
        bw.Write((short)0);      // planes
        bw.Write((short)32);     // bit depth
        bw.Write(png.Length);    // image data size
        bw.Write(22);            // offset to image data (6 + 16)

        bw.Write(png);
        ms.Position = 0;

        return new System.Drawing.Icon(ms, size, size);
    }
}
