using SkiaSharp;
using SkiaSharp.Views.Desktop;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Claudario.Windows.Mascot;
using SkiaSharp.Views.WPF;

namespace Claudario.Windows.Overlay;

public partial class OverlayWindow : Window
{
    // WS_EX flags for click-through transparency
    private const int GWL_EXSTYLE     = -20;
    private const int WS_EX_LAYERED   = 0x00080000;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_NOACTIVATE  = 0x08000000;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hwnd, int nIndex);
    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hwnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT pt);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    private readonly MascotScene _scene;
    private IntPtr _hwnd;

    public MascotScene Scene => _scene;

    public OverlayWindow()
    {
        InitializeComponent();
        _scene = new MascotScene();

        Loaded += OnLoaded;
        CompositionTarget.Rendering += OnRendering;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;

        // Start as click-through; toggled per-frame based on cursor position
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);

        PositionToTaskbar();
    }

    private void PositionToTaskbar()
    {
        var info = TaskbarGeometry.Current();
        var r = info.StripRect;
        Left   = r.Left;
        Top    = r.Top;
        Width  = r.Width;
        Height = r.Height;
    }

    // Called every frame by CompositionTarget.Rendering
    private void OnRendering(object? sender, EventArgs e)
    {
        UpdateClickThrough();
        SkElement.InvalidateVisual();
    }

    private void UpdateClickThrough()
    {
        if (_hwnd == IntPtr.Zero) return;

        // Determine if cursor is over the mascot's bounding rect (in screen pixels)
        GetCursorPos(out var pt);
        var mascotScreen = GetMascotScreenRect();
        bool overMascot = mascotScreen.Contains(pt.X, pt.Y);

        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        int desired = overMascot
            ? (ex & ~WS_EX_TRANSPARENT)                          // allow clicks through to mascot
            : (ex | WS_EX_TRANSPARENT);                          // pass clicks through to taskbar

        if (ex != desired)
            SetWindowLong(_hwnd, GWL_EXSTYLE, desired);
    }

    // Returns mascot bounding rect in screen pixel coordinates
    private System.Drawing.Rectangle GetMascotScreenRect()
    {
        double dpi = GetDpi();
        double scale = dpi / 96.0;

        // Scene coordinates: mascot sits at center-x, groundY from bottom
        double sceneW = Width;
        double sceneH = Height;
        double s = _scene.MascotSize;
        double mx = _scene.MascotX;
        double my = MascotScene.GroundY;

        // Convert scene coords (Y=0 at bottom) to screen pixels
        double screenLeft   = (Left + mx - s / 2) * scale;
        double screenTop    = (Top  + sceneH - my - s) * scale;
        double screenWidth  = s * scale;
        double screenHeight = s * scale;

        return new System.Drawing.Rectangle(
            (int)screenLeft, (int)screenTop,
            (int)(screenWidth + 1), (int)(screenHeight + 1));
    }

    private double GetDpi()
    {
        var src = PresentationSource.FromVisual(this);
        return src?.CompositionTarget?.TransformToDevice.M11 * 96.0 ?? 96.0;
    }

    private void OnPaintSurface(object sender, SKPaintSurfaceEventArgs e)
    {
        _scene.Draw(e.Surface.Canvas, e.Info.Width, e.Info.Height);
    }
}
