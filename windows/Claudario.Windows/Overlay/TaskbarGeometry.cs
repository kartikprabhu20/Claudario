using System.Runtime.InteropServices;
using System.Windows;

namespace Claudario.Windows.Overlay;

public enum TaskbarEdge { Bottom, Top, Left, Right }

public record TaskbarInfo(TaskbarEdge Edge, Rect StripRect);

public static class TaskbarGeometry
{
    // Extra headroom above taskbar so jumps and tall props aren't clipped.
    // Matches macOS DockGeometry.heightMultiplier = 2.
    public const double HeightMultiplier = 2.0;
    public const double FallbackStripHeight = 80;

    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public int lParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int left, top, right, bottom; }

    [DllImport("shell32.dll")]
    private static extern IntPtr SHAppBarMessage(uint dwMessage, ref AppBarData pData);

    private const uint ABM_GETTASKBARPOS = 5;

    public static TaskbarInfo Current()
    {
        var data = new AppBarData { cbSize = (uint)Marshal.SizeOf<AppBarData>() };
        SHAppBarMessage(ABM_GETTASKBARPOS, ref data);

        // Convert pixels → WPF device-independent units (DPI-aware via GetDpiForSystem)
        double dpi = GetSystemDpi();
        double scale = dpi / 96.0;

        var r = data.rc;
        double left   = r.left   / scale;
        double top    = r.top    / scale;
        double right  = r.right  / scale;
        double bottom = r.bottom / scale;

        // Screen bounds for fallback
        double screenW = SystemParameters.PrimaryScreenWidth;
        double screenH = SystemParameters.PrimaryScreenHeight;

        TaskbarEdge edge;
        double stripH, stripW, stripX, stripY;

        // Determine edge from taskbar rect position
        if (bottom >= screenH - 2 && top > 0)
        {
            edge = TaskbarEdge.Bottom;
            double taskbarH = bottom - top;
            if (taskbarH < 4) taskbarH = FallbackStripHeight / HeightMultiplier;
            stripH = taskbarH * HeightMultiplier;
            stripW = screenW;
            stripX = 0;
            stripY = top - stripH; // bottom of strip = top of taskbar; never overlaps taskbar
        }
        else if (top <= 2 && bottom < screenH - 2 && left <= 2 && right < screenW - 2)
        {
            edge = TaskbarEdge.Top;
            double taskbarH = bottom - top;
            if (taskbarH < 4) taskbarH = FallbackStripHeight / HeightMultiplier;
            stripH = taskbarH * HeightMultiplier;
            stripW = screenW;
            stripX = 0;
            stripY = bottom; // top of strip = bottom of taskbar
        }
        else if (left <= 2 && right < screenW / 2)
        {
            edge = TaskbarEdge.Left;
            stripH = FallbackStripHeight;
            stripW = (right - left) * HeightMultiplier;
            stripX = 0;
            stripY = (screenH - stripH) / 2;
        }
        else
        {
            edge = TaskbarEdge.Right;
            stripH = FallbackStripHeight;
            stripW = (right - left) * HeightMultiplier;
            stripX = screenW - stripW;
            stripY = (screenH - stripH) / 2;
        }

        return new TaskbarInfo(edge, new Rect(stripX, stripY, stripW, stripH));
    }

    [DllImport("user32.dll")]
    private static extern int GetDpiForSystem();

    private static double GetSystemDpi()
    {
        try { return GetDpiForSystem(); }
        catch { return 96; }
    }
}
