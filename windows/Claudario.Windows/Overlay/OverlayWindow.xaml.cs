using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using System.Windows.Interop;
using System.Windows.Media;
using Claudario.Windows.Mascot;
using Claudario.Windows.Settings;
using SkiaSharp.Views.Desktop;
using SkiaSharp.Views.WPF;

namespace Claudario.Windows.Overlay;

public partial class OverlayWindow : Window
{
    // ── Win32 constants ───────────────────────────────────────────────────────
    private const int GWL_EXSTYLE       = -20;
    private const int WS_EX_LAYERED     = 0x00080000;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_NOACTIVATE  = 0x08000000;
    private const int WH_MOUSE_LL       = 14;
    private const int WM_LBUTTONDOWN    = 0x0201;

    [DllImport("user32.dll")] static extern int    GetWindowLong(IntPtr h, int n);
    [DllImport("user32.dll")] static extern int    SetWindowLong(IntPtr h, int n, int v);
    [DllImport("user32.dll")] static extern bool   GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, LowLevelMouseProc fn, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern bool   UnhookWindowsHookEx(IntPtr hk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hk, int code, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string? name);

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct MSLLHOOKSTRUCT
        { public int X, Y; public uint mouseData, flags, time; public IntPtr extra; }

    private delegate IntPtr LowLevelMouseProc(int code, IntPtr w, IntPtr l);

    // ── Fields ────────────────────────────────────────────────────────────────
    private readonly MascotScene    _scene;
    private readonly MascotSettings _settings;
    private IntPtr _hwnd;

    private bool _leftHeld  = false;
    private bool _rightHeld = false;

    // Static so GC never collects the delegate while the hook is live.
    // The hook is installed for the lifetime of the window (not just Controlled mode)
    // so that click-on-mascot is intercepted before Windows routes it — this avoids
    // the per-frame WS_EX_TRANSPARENT race condition.
    private static LowLevelMouseProc? _hookProc;
    private static IntPtr             _hookHandle = IntPtr.Zero;
    private static WeakReference<OverlayWindow>? _hookOwner;

    public MascotScene Scene => _scene;

    // ── Activity key map: keys 1-9, 0 → MascotActivity cases (matches macOS order)
    private static readonly (Key key, MascotActivity activity)[] ActivityKeys =
    [
        (Key.D1, MascotActivity.Idle),
        (Key.D2, MascotActivity.Thinking),
        (Key.D3, MascotActivity.Reading),
        (Key.D4, MascotActivity.Coding),
        (Key.D5, MascotActivity.Running),
        (Key.D6, MascotActivity.Planning),
        (Key.D7, MascotActivity.Browsing),
        (Key.D8, MascotActivity.DeepThink),
        (Key.D9, MascotActivity.Compacting),
        (Key.D0, MascotActivity.Dancing),
    ];

    // ── Constructor ───────────────────────────────────────────────────────────

    public OverlayWindow(MascotSettings settings)
    {
        _settings = settings;
        _scene    = new MascotScene();

        _scene.SetColor(_settings.ColorIndex);
        _scene.SetVariant(_settings.VariantIndex);
        _scene.SetSize(_settings.Size);

        InitializeComponent();
        Loaded  += OnLoaded;
        Closing += (_, _) => RemoveMouseHook();
        CompositionTarget.Rendering += OnRendering;
    }

    // ── Startup ───────────────────────────────────────────────────────────────

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
        PositionToTaskbar();
        InstallMouseHook(); // permanent — handles both enter and exit of Controlled mode
    }

    private void PositionToTaskbar()
    {
        var r = TaskbarGeometry.Current().StripRect;
        Left = r.Left; Top = r.Top; Width = r.Width; Height = r.Height;
    }

    // ── Per-frame ─────────────────────────────────────────────────────────────

    private void OnRendering(object? sender, EventArgs e)
    {
        _scene.Update();
        UpdateClickThrough();
        SkElement.InvalidateVisual();
    }

    private void UpdateClickThrough()
    {
        if (_hwnd == IntPtr.Zero) return;

        bool capture = _scene.State switch
        {
            MascotState.Playing    => true,
            MascotState.Controlled => true,
            MascotState.Walking    => false,
            _ => MascotScreenRect().Contains(GetCursorScreenPos()),
        };

        int ex      = GetWindowLong(_hwnd, GWL_EXSTYLE);
        int desired = capture ? (ex & ~WS_EX_TRANSPARENT) : (ex | WS_EX_TRANSPARENT);
        if (ex != desired) SetWindowLong(_hwnd, GWL_EXSTYLE, desired);
    }

    // ── Keyboard ──────────────────────────────────────────────────────────────

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (_scene.State == MascotState.Controlled)
            HandleControlledKey(e.Key, isRepeat: e.IsRepeat);
    }

    private void OnKeyUp(object sender, KeyEventArgs e)
    {
        if (_scene.State != MascotState.Controlled) return;
        switch (e.Key)
        {
            case Key.Left:  _leftHeld  = false; ApplyMoveDir(); break;
            case Key.Right: _rightHeld = false; ApplyMoveDir(); break;
        }
    }

    private void HandleControlledKey(Key key, bool isRepeat)
    {
        switch (key)
        {
            case Key.Escape:
                ReleaseControl();
                break;

            case Key.Left:
                _leftHeld = true;
                ApplyMoveDir();
                break;

            case Key.Right:
                _rightHeld = true;
                ApplyMoveDir();
                break;

            case Key.Up when !isRepeat:
                _scene.UserJump();
                break;

            case Key.C when !isRepeat:
                _scene.SetColor(_settings.CycleColor());
                break;

            case Key.V when !isRepeat:
                _scene.SetVariant(_settings.CycleVariant());
                break;

            case Key.OemComma:
                _scene.SetSize(_settings.NudgeSize(-1));
                break;

            case Key.OemPeriod:
                _scene.SetSize(_settings.NudgeSize(+1));
                break;

            default:
                if (!isRepeat)
                    foreach (var (k, act) in ActivityKeys)
                        if (key == k) { _scene.SetActivity(act); return; }
                break;
        }
    }

    private void ApplyMoveDir()
    {
        double dir = (_leftHeld, _rightHeld) switch
        {
            (true,  false) => -1,
            (false, true)  =>  1,
            _              =>  0,
        };
        _scene.SetUserMove(dir);
    }

    // ── Controlled-mode lifecycle ─────────────────────────────────────────────

    private void EnterControlled()
    {
        if (_scene.State == MascotState.Controlled) return;

        // Remove NOACTIVATE so the window can receive keyboard focus
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex & ~WS_EX_NOACTIVATE);

        Activate();
        Focus();

        _scene.SetState(MascotState.Controlled);
        // Hook is already installed at startup — no need to install here
    }

    private void ReleaseControl()
    {
        if (_scene.State != MascotState.Controlled) return;
        TearDownControl();
        _scene.SetState(MascotState.Idle);
    }

    private void TearDownControl()
    {
        _leftHeld = _rightHeld = false;
        _scene.SetUserMove(0);
        // Hook stays installed — only removed when window closes

        // Restore NOACTIVATE
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE);
    }

    // ── Low-level mouse hook ──────────────────────────────────────────────────
    // Installed for the full window lifetime. Handles two cases:
    //   Idle + click on mascot → EnterControlled (click consumed so background is unaffected)
    //   Controlled + click outside mascot → ReleaseControl

    private void InstallMouseHook()
    {
        if (_hookHandle != IntPtr.Zero) return;
        _hookOwner  = new WeakReference<OverlayWindow>(this);
        _hookProc   = GlobalMouseCallback;
        _hookHandle = SetWindowsHookEx(WH_MOUSE_LL, _hookProc, GetModuleHandle(null), 0);
    }

    private static void RemoveMouseHook()
    {
        if (_hookHandle == IntPtr.Zero) return;
        UnhookWindowsHookEx(_hookHandle);
        _hookHandle = IntPtr.Zero;
        _hookProc   = null;
        _hookOwner  = null;
    }

    private static IntPtr GlobalMouseCallback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 && wParam == WM_LBUTTONDOWN
            && _hookOwner is not null
            && _hookOwner.TryGetTarget(out var owner))
        {
            var s = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            bool overMascot = owner.MascotScreenRect().Contains(s.X, s.Y);

            if (overMascot && owner._scene.State == MascotState.Idle)
            {
                owner.Dispatcher.BeginInvoke(owner.EnterControlled);
                // Return non-zero without calling next hook to consume the click,
                // preventing the background window from also receiving it.
                return new IntPtr(1);
            }

            if (!overMascot && owner._scene.State == MascotState.Controlled)
                owner.Dispatcher.BeginInvoke(owner.ReleaseControl);
        }
        return CallNextHookEx(_hookHandle, code, wParam, lParam);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private System.Drawing.Rectangle MascotScreenRect()
    {
        double scale = GetDpiScale();
        var (left, _, right, top_s) = _scene.MascotBounds();
        double s = _scene.MascotSize;

        // Window.Left/Top/Height are WPF DIPs; MascotBounds values are canvas physical pixels.
        // Multiply only the DIP values by scale; canvas values are already in physical pixels.
        double sl = Left   * scale + left;
        double st = (Top + Height) * scale - top_s;
        double sw = right - left;
        double sh = s;
        return new System.Drawing.Rectangle((int)sl, (int)st, (int)(sw + 1), (int)(sh + 1));
    }

    private System.Drawing.Point GetCursorScreenPos()
    {
        GetCursorPos(out var pt);
        return new System.Drawing.Point(pt.X, pt.Y);
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
