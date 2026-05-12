using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Claudario.Windows.Mascot;
using SkiaSharp.Views.Desktop;
using SkiaSharp.Views.WPF;

namespace Claudario.Windows.Overlay;

public partial class OverlayWindow : Window
{
    private const int GWL_EXSTYLE      = -20;
    private const int WS_EX_LAYERED    = 0x00080000;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_NOACTIVATE  = 0x08000000;

    [DllImport("user32.dll")] static extern int  GetWindowLong(IntPtr hwnd, int n);
    [DllImport("user32.dll")] static extern int  SetWindowLong(IntPtr hwnd, int n, int v);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT pt);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    private readonly MascotScene _scene = new();
    private IntPtr _hwnd;

    public MascotScene Scene => _scene;

    public OverlayWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        CompositionTarget.Rendering += OnRendering;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
        PositionToTaskbar();
    }

    private void PositionToTaskbar()
    {
        var r = TaskbarGeometry.Current().StripRect;
        Left = r.Left; Top = r.Top; Width = r.Width; Height = r.Height;
    }

    private void OnRendering(object? sender, EventArgs e)
    {
        _scene.Update();
        UpdateClickThrough();
        SkElement.InvalidateVisual();
    }

    private void UpdateClickThrough()
    {
        if (_hwnd == IntPtr.Zero) return;

        GetCursorPos(out var pt);
        bool overMascot = MascotScreenRect().Contains(pt.X, pt.Y);

        int ex      = GetWindowLong(_hwnd, GWL_EXSTYLE);
        int desired = overMascot ? (ex & ~WS_EX_TRANSPARENT) : (ex | WS_EX_TRANSPARENT);
        if (ex != desired) SetWindowLong(_hwnd, GWL_EXSTYLE, desired);
    }

    private System.Drawing.Rectangle MascotScreenRect()
    {
        double scale = GetDpiScale();
        var (left, _, right, top_scene) = _scene.MascotBounds();
        double s = _scene.MascotSize;

        // Scene: Y=0 at strip bottom, Y increases up → convert to screen pixels
        double screenLeft = (Left + left)   * scale;
        double screenTop  = (Top  + Height - top_scene - s) * scale;
        double w = (right - left) * scale;
        double h = s * scale;

        return new System.Drawing.Rectangle((int)screenLeft, (int)screenTop,
                                             (int)(w + 1),   (int)(h + 1));
    }

    private double GetDpiScale()
    {
        var src = PresentationSource.FromVisual(this);
        return src?.CompositionTarget?.TransformToDevice.M11 ?? 1.0;
    }

    private void OnPaintSurface(object sender, SKPaintSurfaceEventArgs e)
    {
        _scene.Draw(e.Surface.Canvas, e.Info.Width, e.Info.Height);
    }
}
