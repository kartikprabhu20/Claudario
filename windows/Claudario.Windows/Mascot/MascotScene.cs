using SkiaSharp;

namespace Claudario.Windows.Mascot;

/// <summary>
/// Drives all mascot animation state and renders each frame via Draw().
/// Animation is purely time-driven — no node tree, no SpriteKit.
/// Canvas convention inside mascot-local transform: X centered on 0,
/// Y=0 at body bottom, Y increases upward (Scale(1,-1) applied).
/// </summary>
public class MascotScene
{
    // ── Constants ────────────────────────────────────────────────────────────
    public const double GroundY    = 4;   // px from strip bottom where feet rest
    private const double BaseWalk  = 110; // px/s walk speed at 1× multiplier

    // ── Public state ─────────────────────────────────────────────────────────
    public MascotState    State    { get; private set; } = MascotState.Idle;
    public MascotActivity Activity { get; private set; } = MascotActivity.Idle;
    public double MascotSize { get; private set; } = 44;
    public double MascotX    { get; private set; }      // center-x in scene px

    // ── Variant / color ───────────────────────────────────────────────────────
    private int _variantIndex = 0;
    private int _colorIndex   = 0;
    private MascotVariant Variant =>
        (MascotVariant)Math.Clamp(_variantIndex, 0, 6);

    // ── Walk ──────────────────────────────────────────────────────────────────
    private double _walkDir    = 1;     // +1 = right, -1 = left
    private bool   _facingRight = true;
    private double _sceneW;

    // ── Feet ──────────────────────────────────────────────────────────────────
    private double _footTimer   = 0;
    private bool   _leftFootUp  = false;
    private bool   _feetActive  = false;

    // ── Jump / bounce animation ───────────────────────────────────────────────
    private double _jumpOffset     = 0;
    private double _jumpT          = 0;   // elapsed within current half-bounce
    private double _jumpHalfDur    = 0.18;
    private int    _jumpHalf       = 0;   // which half (0=up, 1=down), then repeat
    private int    _jumpTotalHalfs = 0;
    private double _jumpAmp        = 0;

    // ── Blink (idle) ──────────────────────────────────────────────────────────
    // Sequence mirrors macOS: wait, blink, wait, blink, wait, blink, blink, wait
    private static readonly (bool isBlink, double dur)[] BlinkSeq =
    [
        (false, 3.6), (true, 0.16),
        (false, 4.2), (true, 0.16),
        (false, 2.7), (true, 0.16),
        (true,  0.16),
        (false, 5.3),
    ];
    private int    _blinkIdx = 0;
    private double _blinkT   = 0;
    public  double EyeScaleY { get; private set; } = 1;

    // ── Glance (idle) ─────────────────────────────────────────────────────────
    // Mirrors macOS: wait→ease +3→wait→ease -6→wait→ease +3→wait (loop)
    private static readonly (double target, double dur)[] GlanceSeq =
    [
        (0,  2.40), // wait at 0
        (3,  0.28), // ease to +3
        (3,  1.30), // wait at +3
        (-3, 0.40), // ease to -3
        (-3, 1.60), // wait at -3
        (0,  0.28), // ease back to 0
        (0,  4.50), // wait at 0
    ];
    private int    _glanceIdx   = 0;
    private double _glanceT     = 0;
    private double _glanceStart = 0;
    public  double PupilOffsetX { get; private set; } = 0;
    public  double PupilScaleY  { get; private set; } = 1;

    // ── Time ──────────────────────────────────────────────────────────────────
    private DateTime _lastUpdate = DateTime.UtcNow;

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    public void SetState(MascotState state)
    {
        if (State == state) return;
        State = state;

        _feetActive = false;
        _footTimer  = 0;

        if (state == MascotState.Walking)
            BeginNextLeg();
        else if (state == MascotState.Idle)
            ResetBodyAnimState();
    }

    public void SetActivity(MascotActivity activity)
    {
        Activity = activity;
        // Full per-activity animation in Phase 3; for now just reflect the prop.
    }

    public void SetSize(int pts)
    {
        MascotSize = Math.Clamp(pts, 24, 88);
    }

    public void SetColor(int index)
    {
        _colorIndex = ((index % 10) + 10) % 10;
    }

    public void SetVariant(int index)
    {
        _variantIndex = ((index % 7) + 7) % 7;
    }

    public void Celebrate() => StartJump(amplitude: 36, bounces: 1);
    public void Notify()    => StartJump(amplitude: 14, bounces: 2);

    // ─────────────────────────────────────────────────────────────────────────
    // Update (called every frame from OverlayWindow.OnRendering)
    // ─────────────────────────────────────────────────────────────────────────

    public void Update()
    {
        var now = DateTime.UtcNow;
        double dt = Math.Min((now - _lastUpdate).TotalSeconds, 0.1);
        _lastUpdate = now;

        TickWalk(dt);
        TickFeet(dt);
        TickBlink(dt);
        TickGlance(dt);
        TickJump(dt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Animation ticks
    // ─────────────────────────────────────────────────────────────────────────

    private void TickWalk(double dt)
    {
        if (State != MascotState.Walking || _sceneW <= 0) return;

        double mult = Activity.SpeedMultiplier();
        if (mult == 0) mult = 1;
        double speed = BaseWalk * mult;
        double margin = MascotSize / 2 + 8;
        double leftEdge  = margin;
        double rightEdge = Math.Max(margin + 1, _sceneW - margin);

        double step = speed * dt * _walkDir;
        MascotX += step;

        if (_walkDir > 0 && MascotX >= rightEdge)
        {
            MascotX    = rightEdge;
            _walkDir   = -1;
            _facingRight = false;
            BeginNextLeg();
        }
        else if (_walkDir < 0 && MascotX <= leftEdge)
        {
            MascotX    = leftEdge;
            _walkDir   = 1;
            _facingRight = true;
            BeginNextLeg();
        }
    }

    private void BeginNextLeg()
    {
        if (_sceneW <= 0) return;
        double margin = MascotSize / 2 + 8;
        double leftEdge  = margin;
        double rightEdge = Math.Max(margin + 1, _sceneW - margin);
        if (MascotX <= 0) MascotX = leftEdge;

        _feetActive = true;
        _facingRight = _walkDir > 0;
    }

    private void TickFeet(double dt)
    {
        if (!_feetActive) return;
        _footTimer += dt;
        if (_footTimer >= 0.18)
        {
            _footTimer -= 0.18;
            _leftFootUp = !_leftFootUp;
        }
    }

    private void TickBlink(double dt)
    {
        if (State != MascotState.Idle) { EyeScaleY = 1; return; }

        _blinkT += dt;
        var (isBlink, dur) = BlinkSeq[_blinkIdx];

        if (isBlink)
        {
            double p = Math.Clamp(_blinkT / dur, 0, 1);
            // close in first 44% of duration, open in remaining 56%
            EyeScaleY = p < 0.44
                ? 1 - p / 0.44 * (1 - 0.12)
                : 0.12 + (p - 0.44) / 0.56 * (1 - 0.12);
        }
        else
        {
            EyeScaleY = 1;
        }

        if (_blinkT >= dur)
        {
            _blinkT  -= dur;
            _blinkIdx = (_blinkIdx + 1) % BlinkSeq.Length;
        }
    }

    private void TickGlance(double dt)
    {
        if (State != MascotState.Idle) { PupilOffsetX = 0; return; }

        _glanceT += dt;
        var (target, dur) = GlanceSeq[_glanceIdx];

        if (_glanceT >= dur)
        {
            PupilOffsetX  = target;
            _glanceStart  = target;
            _glanceT     -= dur;
            _glanceIdx    = (_glanceIdx + 1) % GlanceSeq.Length;
        }
        else
        {
            double p = _glanceT / dur;
            p = p * p * (3 - 2 * p); // smooth-step
            PupilOffsetX = _glanceStart + (target - _glanceStart) * p;
        }
    }

    private void StartJump(double amplitude, int bounces)
    {
        _jumpAmp        = amplitude;
        _jumpTotalHalfs = bounces * 2;
        _jumpHalf       = 0;
        _jumpT          = 0;
        _jumpOffset     = 0;
    }

    private void TickJump(double dt)
    {
        if (_jumpHalf >= _jumpTotalHalfs) { _jumpOffset = 0; return; }
        _jumpT += dt;
        double p = Math.Clamp(_jumpT / _jumpHalfDur, 0, 1);
        // going up on even halves, down on odd
        bool goingUp = _jumpHalf % 2 == 0;
        // ease-out up, ease-in down
        double eased = goingUp ? 1 - (1 - p) * (1 - p) : p * p;
        _jumpOffset = goingUp ? _jumpAmp * eased : _jumpAmp * (1 - eased);

        if (_jumpT >= _jumpHalfDur)
        {
            _jumpT  -= _jumpHalfDur;
            _jumpHalf++;
        }
    }

    private void ResetBodyAnimState()
    {
        _footTimer  = 0;
        _feetActive = false;
        _leftFootUp = false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Draw
    // ─────────────────────────────────────────────────────────────────────────

    public void Draw(SKCanvas canvas, int pixelW, int pixelH)
    {
        canvas.Clear(SKColors.Transparent);

        _sceneW = pixelW;
        if (MascotX <= 0) MascotX = pixelW * 0.1;

        var palette = MascotPalette.Colors[_colorIndex];
        var variant = Variant;
        float s     = (float)MascotSize;

        // Canvas-space Y of the mascot's body bottom
        float groundCanvas = pixelH - (float)GroundY;
        float bobY = (float)(_jumpOffset);

        // ── Set up mascot-local transform ────────────────────────────────────
        // (0,0) = body bottom-center, Y increases upward, X flipped if facing left
        canvas.Save();
        canvas.Translate((float)MascotX, groundCanvas - bobY);
        canvas.Scale(_facingRight ? 1f : -1f, -1f);

        DrawBody(canvas, s, palette, variant);
        variant.DrawDecorations(canvas, s, palette);
        DrawEyes(canvas, s, variant);
        DrawFeet(canvas, s, palette);

        canvas.Restore();

        // ── Prop label (screen space, not in mascot transform) ───────────────
        string prop = Activity.Prop();
        if (!string.IsNullOrEmpty(prop))
            DrawProp(canvas, prop, (float)MascotX, groundCanvas - bobY - s, s);
    }

    private static void DrawBody(SKCanvas canvas, float s, MascotColor palette, MascotVariant variant)
    {
        using var bodyPath = variant.BodyPath(s);

        using var fill = new SKPaint { Color = palette.Body, IsAntialias = true };
        canvas.DrawPath(bodyPath, fill);

        using var stroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 115), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1.5f,
        };
        canvas.DrawPath(bodyPath, stroke);
    }

    private void DrawEyes(SKCanvas canvas, float s, MascotVariant variant)
    {
        float eyeR  = s * 0.12f;
        float pupilR = eyeR * 0.55f;
        float eyeY  = variant.EyeY(s);
        float eyeScaleY = (float)EyeScaleY;
        float pupilOX   = (float)PupilOffsetX;

        using var eyeFill    = new SKPaint { Color = SKColors.White, IsAntialias = true };
        using var eyeStroke  = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 153), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };
        using var pupilFill  = new SKPaint { Color = SKColors.Black, IsAntialias = true };

        foreach (float ex in new[] { -s * 0.2f, s * 0.2f })
        {
            // Eye white — squished during blink
            canvas.Save();
            canvas.Translate(ex, eyeY);
            canvas.Scale(1f, eyeScaleY);
            canvas.DrawCircle(0, 0, eyeR, eyeFill);
            canvas.DrawCircle(0, 0, eyeR, eyeStroke);
            canvas.Restore();

            // Pupil — slightly right of center, with glance offset
            float px = ex + pupilR * 0.3f + pupilOX;
            canvas.Save();
            canvas.Translate(px, eyeY);
            canvas.Scale(1f, eyeScaleY);
            canvas.DrawCircle(0, 0, pupilR, pupilFill);
            canvas.Restore();
        }
    }

    private void DrawFeet(SKCanvas canvas, float s, MascotColor palette)
    {
        float footW = s * 0.28f, footH = s * 0.14f;
        float leftY  = _leftFootUp  ? 4f : 0f;
        float rightY = !_leftFootUp ? 4f : 0f;

        using var fill = new SKPaint { Color = palette.Foot, IsAntialias = true };
        using var stroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 128), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };

        DrawFoot(canvas, -s * 0.2f, leftY,  footW, footH, fill, stroke);
        DrawFoot(canvas,  s * 0.2f, rightY, footW, footH, fill, stroke);
    }

    private static void DrawFoot(SKCanvas c, float fx, float offsetY,
        float fw, float fh, SKPaint fill, SKPaint stroke)
    {
        // In mascot-local coords: feet sit at y=0 (body bottom), offsetY lifts one foot
        var r = new SKRect(fx - fw / 2, offsetY - fh, fx + fw / 2, offsetY);
        c.DrawRoundRect(r, fh / 2, fh / 2, fill);
        c.DrawRoundRect(r, fh / 2, fh / 2, stroke);
    }

    private static void DrawProp(SKCanvas canvas, string prop, float cx, float topY, float s)
    {
        // topY is the canvas-Y of the mascot body top; prop floats above it
        float propY = topY - s * 0.15f; // a bit of gap above body

        using var font = new SKFont(SKTypeface.Default, s * 0.5f);
        using var paint = new SKPaint { IsAntialias = true, TextAlign = SKTextAlign.Center };
        canvas.DrawText(prop, cx, propY, font, paint);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers used by OverlayWindow for click-through hit testing
    // ─────────────────────────────────────────────────────────────────────────

    // Mascot bounding box in scene coords (Y=0 at strip bottom, Y increases up)
    public (double left, double top, double right, double bottom) MascotBounds()
    {
        double s = MascotSize;
        return (MascotX - s / 2, GroundY, MascotX + s / 2, GroundY + s + _jumpOffset);
    }
}
