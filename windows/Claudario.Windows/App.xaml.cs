using System.Windows;
using Application = System.Windows.Application;
using Claudario.Windows.Mascot;
using Claudario.Windows.Overlay;
using Claudario.Windows.Server;
using Claudario.Windows.Settings;

namespace Claudario.Windows;

public partial class App : Application
{
    private System.Windows.Forms.NotifyIcon? _tray;
    private OverlayWindow? _overlay;
    private EventServer?   _server;
    private EventRouter?   _router;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _tray = new System.Windows.Forms.NotifyIcon
        {
            Icon    = CreateTrayIcon(),
            Text    = "Claudario",
            Visible = true,
        };
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("Quit", null, (_, _) => Shutdown());
        _tray.ContextMenuStrip = menu;

        var settings = new MascotSettings();
        _overlay = new OverlayWindow(settings);
        _overlay.Show();

        StartServer();
    }

    private void StartServer()
    {
        _router = new EventRouter();

        _router.OnWalk = () =>
        {
            System.Diagnostics.Debug.WriteLine("→ OnWalk");
            _overlay?.Scene.SetState(MascotState.Walking);
        };
        _router.OnIdle = () =>
        {
            System.Diagnostics.Debug.WriteLine("→ OnIdle");
            _overlay?.Scene.SetState(MascotState.Idle);
        };
        _router.OnCelebrate = () =>
        {
            System.Diagnostics.Debug.WriteLine("→ OnCelebrate");
            _overlay?.Scene.Celebrate();
        };
        _router.OnNotify = () =>
        {
            System.Diagnostics.Debug.WriteLine("→ OnNotify");
            _overlay?.Scene.Notify();
        };
        _router.OnActivity = activity =>
        {
            System.Diagnostics.Debug.WriteLine($"→ OnActivity: {activity}");
            _overlay?.Scene.SetActivity(activity);
        };

        _server = new EventServer(_router);
        _server.Start(port =>
            System.Diagnostics.Debug.WriteLine($"Claudario: listening on port {port}"));
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _server?.Dispose();
        if (_tray != null) { _tray.Visible = false; _tray.Dispose(); }
        base.OnExit(e);
    }

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

        IntPtr hIcon = bmp.GetHicon();
        return System.Drawing.Icon.FromHandle(hIcon);
    }
}
