using SkiaSharp;

namespace Claudario.Windows.Mascot;

/// <summary>
/// Drives all mascot animation and renders each frame via Draw().
/// All animation is time-driven — no node tree, no SpriteKit.
/// Canvas convention inside mascot-local transform: X centered on 0,
/// Y=0 at body bottom, Y increases upward (Scale(±1,-1) applied by Draw).
/// </summary>
public class MascotScene
{
    // ── Constants ─────────────────────────────────────────────────────────────
    public const double GroundY   = 4;    // px from strip bottom where feet rest
    private const double BaseWalk = 110;  // px/s at 1× speed multiplier

    // ── Public state ──────────────────────────────────────────────────────────
    public MascotState    State    { get; private set; } = MascotState.Idle;
    public MascotActivity Activity { get; private set; } = MascotActivity.Idle;
    public double MascotSize { get; private set; } = 44;
    public double MascotX    { get; private set; }      // center-x in scene px

    // ── Variant / color ───────────────────────────────────────────────────────
    private int _variantIndex = 0;
    private int _colorIndex   = 0;
    private MascotVariant Variant =>
        (MascotVariant)Math.Clamp(_variantIndex, 0, 6);

    // ── Walk / controlled movement ────────────────────────────────────────────
    private double _walkDir      = 1;
    private bool   _facingRight  = true;
    private double _sceneW;
    private double _userMoveDir  = 0;   // -1/0/+1, set by keyboard in Controlled state

    // ── Feet ──────────────────────────────────────────────────────────────────
    private double _footTimer  = 0;
    private bool   _leftFootUp = false;
    private bool   _feetActive = false;

    // ── Jump / bounce ─────────────────────────────────────────────────────────
    private double _jumpOffset     = 0;
    private double _jumpT          = 0;
    private double _jumpHalfDur    = 0.18;
    private int    _jumpHalf       = 0;
    private int    _jumpTotalHalfs = 0;
    private double _jumpAmp        = 0;

    // ── Idle blink ────────────────────────────────────────────────────────────
    // Pattern mirrors macOS: 3.6s wait → blink → 4.2s → blink → 2.7s →
    //   blink → blink (double) → 5.3s (loop).  One blink = 0.07s close + 0.09s open.
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
    private double _idleEyeScaleY = 1;  // output of the blink sequencer

    // ── Idle glance ───────────────────────────────────────────────────────────
    // wait→ease +3→wait→ease -6→wait→ease +3→wait (loop)
    private static readonly (double target, double dur)[] GlanceSeq =
    [
        (0,  2.40), (3,  0.28), (3,  1.30),
        (-3, 0.40), (-3, 1.60), (0,  0.28),
        (0,  4.50),
    ];
    private int    _glanceIdx   = 0;
    private double _glanceT     = 0;
    private double _glanceStart = 0;
    private double _idlePupilX  = 0;   // output of the glance sequencer

    // ── Activity animation ────────────────────────────────────────────────────
    // These are reset in SetActivity() and updated each frame in TickActivity().
    private double _actT          = 0;  // monotonic time since last SetActivity()
    private double _actPhaseT     = 0;  // time within current multi-step phase
    private int    _actPhaseIdx   = 0;  // step index for sequenced activities

    // Computed outputs (read by Draw each frame)
    private double _bobOffset   = 0;    // whole-mascot Y offset (bob/dance)
    private double _bodyRot     = 0;    // body-only rotation in radians
    private double _bodyScaleX  = 1;    // body-only X scale
    private double _bodyScaleY  = 1;    // body-only Y scale
    private double _actEyeScale = -1;   // -1 = use idle blink; ≥0 = override
    private double _actPupilX   = 0;    // activity pupil offset (reading scan)
    private double _danceXOff   = 0;    // whole-mascot X offset (dancing)
    private double _danceYOff   = 0;    // whole-mascot Y offset (dancing, added to bob)

    // ── Time ──────────────────────────────────────────────────────────────────
    private DateTime _lastUpdate = DateTime.UtcNow;

    // ═════════════════════════════════════════════════════════════════════════
    // Public API
    // ═════════════════════════════════════════════════════════════════════════

    public void SetState(MascotState state)
    {
        if (State == state) return;
        State = state;
        _feetActive  = false;
        _footTimer   = 0;
        _userMoveDir = 0;
        if (state == MascotState.Walking)    BeginNextLeg();
        if (state == MascotState.Idle)       ClearWalkVisuals();
        if (state == MascotState.Controlled) ClearWalkVisuals();
    }

    // Called by OverlayWindow on arrow-key down/up while in Controlled state.
    public void SetUserMove(double direction)
    {
        if (State != MascotState.Controlled) return;
        _userMoveDir = direction > 0 ? 1 : direction < 0 ? -1 : 0;
        _feetActive  = _userMoveDir != 0;
        if (_userMoveDir != 0) _facingRight = _userMoveDir > 0;
        if (_userMoveDir == 0) { _footTimer = 0; _leftFootUp = false; }
    }

    // User-initiated jump in Controlled state. Returns false if already airborne.
    public bool UserJump()
    {
        if (State != MascotState.Controlled) return false;
        if (_jumpHalf < _jumpTotalHalfs)     return false; // already in a jump
        StartJump(36, bounces: 1);
        return true;
    }

    public void SetActivity(MascotActivity activity)
    {
        if (Activity == activity) return;
        Activity      = activity;
        _actT         = 0;
        _actPhaseT    = 0;
        _actPhaseIdx  = 0;
        _bobOffset    = 0;
        _bodyRot      = 0;
        _bodyScaleX   = 1;
        _bodyScaleY   = 1;
        _actEyeScale  = -1;
        _actPupilX    = 0;
        _danceXOff    = 0;
        _danceYOff    = 0;
    }

    public void SetSize(int pts)    => MascotSize = Math.Clamp(pts, 24, 88);
    public void SetColor(int idx)   => _colorIndex   = ((idx % 10) + 10) % 10;
    public void SetVariant(int idx) => _variantIndex = ((idx % 7)  + 7)  % 7;

    public void Celebrate() => StartJump(36, bounces: 1);
    public void Notify()    => StartJump(14, bounces: 2);

    // ═════════════════════════════════════════════════════════════════════════
    // Update — called every frame from OverlayWindow.OnRendering
    // ═════════════════════════════════════════════════════════════════════════

    public void Update()
    {
        var now = DateTime.UtcNow;
        double dt = Math.Min((now - _lastUpdate).TotalSeconds, 0.1);
        _lastUpdate = now;

        TickWalk(dt);
        TickFeet(dt);
        TickIdleBlink(dt);
        TickIdleGlance(dt);
        TickJump(dt);
        TickActivity(dt);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Animation ticks
    // ═════════════════════════════════════════════════════════════════════════

    private void TickWalk(double dt)
    {
        double margin = MascotSize / 2 + 8;
        double left   = margin;
        double right  = Math.Max(margin + 1, _sceneW - margin);

        if (State == MascotState.Walking && _sceneW > 0)
        {
            double mult  = Activity.SpeedMultiplier();
            double speed = BaseWalk * (mult == 0 ? 1 : mult);
            MascotX += speed * dt * _walkDir;

            if (_walkDir > 0 && MascotX >= right)
            {
                MascotX = right; _walkDir = -1; _facingRight = false; BeginNextLeg();
            }
            else if (_walkDir < 0 && MascotX <= left)
            {
                MascotX = left;  _walkDir = 1;  _facingRight = true;  BeginNextLeg();
            }
        }
        else if (State == MascotState.Controlled && _userMoveDir != 0 && _sceneW > 0)
        {
            MascotX = Math.Clamp(MascotX + BaseWalk * dt * _userMoveDir, left, right);
        }
    }

    private void BeginNextLeg()
    {
        if (_sceneW <= 0) return;
        double margin = MascotSize / 2 + 8;
        if (MascotX <= 0) MascotX = margin;
        _feetActive  = Activity.SpeedMultiplier() != 0; // dancing uses dance offsets, not feet
        _facingRight = _walkDir > 0;
    }

    private void ClearWalkVisuals()
    {
        _feetActive = false;
        _footTimer  = 0;
        _leftFootUp = false;
    }

    private void TickFeet(double dt)
    {
        if (!_feetActive) return;
        _footTimer += dt;
        if (_footTimer >= 0.18) { _footTimer -= 0.18; _leftFootUp = !_leftFootUp; }
    }

    // Idle blink sequencer — output stored in _idleEyeScaleY
    private void TickIdleBlink(double dt)
    {
        _blinkT += dt;
        var (isBlink, dur) = BlinkSeq[_blinkIdx];

        _idleEyeScaleY = isBlink
            ? ComputeBlinkScale(_blinkT / Math.Max(dur, 1e-6))
            : 1.0;

        if (_blinkT >= dur) { _blinkT -= dur; _blinkIdx = (_blinkIdx + 1) % BlinkSeq.Length; }
    }

    private static double ComputeBlinkScale(double p)
    {
        p = Math.Clamp(p, 0, 1);
        // Close in first 44 %, open in remaining 56 %
        return p < 0.44 ? 1 - p / 0.44 * 0.88 : 0.12 + (p - 0.44) / 0.56 * 0.88;
    }

    // Idle glance sequencer — output stored in _idlePupilX
    private void TickIdleGlance(double dt)
    {
        _glanceT += dt;
        var (target, dur) = GlanceSeq[_glanceIdx];

        if (_glanceT >= dur)
        {
            _idlePupilX  = target;
            _glanceStart = target;
            _glanceT    -= dur;
            _glanceIdx   = (_glanceIdx + 1) % GlanceSeq.Length;
        }
        else
        {
            double p = _glanceT / dur;
            p = p * p * (3 - 2 * p); // smoothstep
            _idlePupilX = _glanceStart + (target - _glanceStart) * p;
        }
    }

    private void StartJump(double amp, int bounces)
    {
        _jumpAmp        = amp;
        _jumpTotalHalfs = bounces * 2;
        _jumpHalf       = 0;
        _jumpT          = 0;
    }

    private void TickJump(double dt)
    {
        if (_jumpHalf >= _jumpTotalHalfs) { _jumpOffset = 0; return; }
        _jumpT += dt;
        double p = Math.Clamp(_jumpT / _jumpHalfDur, 0, 1);
        bool up  = _jumpHalf % 2 == 0;
        double e = up ? 1 - (1 - p) * (1 - p) : p * p; // ease-out up, ease-in down
        _jumpOffset = up ? _jumpAmp * e : _jumpAmp * (1 - e);
        if (_jumpT >= _jumpHalfDur) { _jumpT -= _jumpHalfDur; _jumpHalf++; }
    }

    // ── Per-activity animation ────────────────────────────────────────────────

    private void TickActivity(double dt)
    {
        if (Activity == MascotActivity.Idle)
        {
            // Idle uses the blink/glance sequencers; clear all overrides.
            _bobOffset = 0; _bodyRot = 0; _bodyScaleX = 1; _bodyScaleY = 1;
            _actEyeScale = -1; _actPupilX = 0; _danceXOff = 0; _danceYOff = 0;
            return;
        }

        _actT += dt;

        // Default: eyes open (no blink), pupils centered, body neutral
        _actEyeScale = 1; _actPupilX = 0;
        _bobOffset = 0; _bodyRot = 0; _bodyScaleX = 1; _bodyScaleY = 1;
        _danceXOff = 0; _danceYOff = 0;

        switch (Activity)
        {
            case MascotActivity.Thinking:   TickThinking();   break;
            case MascotActivity.Reading:    TickReading();    break;
            case MascotActivity.Coding:     TickCoding();     break;
            case MascotActivity.Running:    TickRunning();    break;
            case MascotActivity.Planning:   TickPlanning();   break;
            case MascotActivity.Browsing:   TickBrowsing();   break;
            case MascotActivity.DeepThink:  TickDeepThink();  break;
            case MascotActivity.Compacting: TickCompacting(); break;
            case MascotActivity.Dancing:    TickDancing(dt);  break;
        }
    }

    // thinking: bob up +4 then back, 0.6s each way
    private void TickThinking()
    {
        double t = _actT % 1.2;
        _bobOffset = t < 0.6 ? 4 * t / 0.6 : 4 * (1.2 - t) / 0.6;
    }

    // reading: pupil scan +3 in 0.4s → -3 in 0.5s → 0 in 0.4s (loop 1.3s)
    private void TickReading()
    {
        double t = _actT % 1.3;
        _actPupilX = t < 0.4  ? Lerp(0,   3, t / 0.4)
                   : t < 0.9  ? Lerp(3,  -3, (t - 0.4) / 0.5)
                   :             Lerp(-3,  0, (t - 0.9) / 0.4);
    }

    // coding: body squash (1.06/0.94) two cycles then rest, loop 0.5s
    private void TickCoding()
    {
        double t = _actT % 0.50;
        if      (t < 0.08) { double p = t / 0.08;         _bodyScaleX = 1 + 0.06*p; _bodyScaleY = 1 - 0.06*p; }
        else if (t < 0.16) { double p = (t-0.08) / 0.08;  _bodyScaleX = 1.06 - 0.06*p; _bodyScaleY = 0.94 + 0.06*p; }
        else if (t < 0.24) { double p = (t-0.16) / 0.08;  _bodyScaleX = 1 + 0.06*p; _bodyScaleY = 1 - 0.06*p; }
        else if (t < 0.32) { double p = (t-0.24) / 0.08;  _bodyScaleX = 1.06 - 0.06*p; _bodyScaleY = 0.94 + 0.06*p; }
        // 0.32–0.50: rest at 1,1 (already default)
    }

    // running: body leans -0.08rad forward and back, 0.18s each way
    private void TickRunning()
    {
        double t = _actT % 0.36;
        _bodyRot = t < 0.18 ? -0.08 * t / 0.18 : -0.08 * (0.36 - t) / 0.18;
    }

    // planning: tilt π/14 → -π/14 → 0 over 2.8s (0.8 + 1.4 + 0.6)
    private void TickPlanning()
    {
        double t = _actT % 2.8;
        double target = Math.PI / 14;
        _bodyRot = t < 0.8  ? Lerp(0,        target,  t / 0.8)
                 : t < 2.2  ? Lerp(target,  -target, (t - 0.8)  / 1.4)
                 :             Lerp(-target,  0,      (t - 2.2)  / 0.6);
    }

    // browsing: eye squint 1→0.4→1 over 1s then wait 0.4s (loop 1.4s)
    private void TickBrowsing()
    {
        double t = _actT % 1.4;
        _actEyeScale = t < 0.5 ? Lerp(1, 0.4,  t / 0.5)
                     : t < 1.0 ? Lerp(0.4, 1, (t - 0.5) / 0.5)
                     : 1.0;
    }

    // deepThink: slow bob (6px, 1.4s each way) + slow blink (0.15s+0.15s close/open, 2.5s wait)
    private void TickDeepThink()
    {
        double t = _actT % 2.8;
        _bobOffset = t < 1.4 ? 6 * t / 1.4 : 6 * (2.8 - t) / 1.4;

        double blinkT = _actT % 2.8;
        _actEyeScale = blinkT < 0.15  ? Lerp(1, 0.15,  blinkT / 0.15)
                     : blinkT < 0.30  ? Lerp(0.15, 1, (blinkT - 0.15) / 0.15)
                     : 1.0;
    }

    // compacting: full 2π rotation of body every 3s
    private void TickCompacting() => _bodyRot = _actT * (2 * Math.PI / 3.0);

    // dancing: hop sequence of 5 keyframes, loops 0.76s
    // Absolute positions: (0,0)→(6,12)→(6,0)→(-6,12)→(-6,0)→(0,0)
    private void TickDancing(double dt)
    {
        _actPhaseT += dt;

        (double dur, (double x0, double y0), (double x1, double y1))[] steps =
        [
            (0.18, (0,0),   (6,12)),
            (0.15, (6,12),  (6,0)),
            (0.18, (6,0),   (-6,12)),
            (0.15, (-6,12), (-6,0)),
            (0.10, (-6,0),  (0,0)),
        ];

        while (_actPhaseT >= steps[_actPhaseIdx].dur)
        {
            _actPhaseT -= steps[_actPhaseIdx].dur;
            _actPhaseIdx = (_actPhaseIdx + 1) % steps.Length;
        }

        var (dur, (x0, y0), (x1, y1)) = steps[_actPhaseIdx];
        double p = _actPhaseT / dur;
        _danceXOff = Lerp(x0, x1, p);
        _danceYOff = Lerp(y0, y1, p);
    }

    private static double Lerp(double a, double b, double t) => a + (b - a) * Math.Clamp(t, 0, 1);

    // ═════════════════════════════════════════════════════════════════════════
    // Draw
    // ═════════════════════════════════════════════════════════════════════════

    public void Draw(SKCanvas canvas, int pixelW, int pixelH)
    {
        canvas.Clear(SKColors.Transparent);

        _sceneW = pixelW;
        if (MascotX <= 0) MascotX = pixelW * 0.1;

        var palette = MascotPalette.Colors[_colorIndex];
        var variant = Variant;
        float s = (float)MascotSize;

        // Resolve effective eye/pupil values
        double eyeScale  = _actEyeScale >= 0 ? _actEyeScale : _idleEyeScaleY;
        double pupilX    = Activity == MascotActivity.Idle ? _idlePupilX : _actPupilX;

        // Canvas-Y of mascot body bottom (strip: Y=0 at top, Y=pixelH at bottom)
        float groundY  = pixelH - (float)GroundY;
        float liftY    = (float)(_jumpOffset + _bobOffset + _danceYOff);
        float shiftX   = (float)_danceXOff;

        // ── Mascot-local transform: (0,0)=body bottom-center, Y up, X flipped if facing left
        canvas.Save();
        canvas.Translate((float)MascotX + shiftX, groundY - liftY);
        canvas.Scale(_facingRight ? 1f : -1f, -1f);

        // Body + decorations share a sub-transform for rotation/squash
        canvas.Save();
        canvas.RotateRadians((float)_bodyRot);
        canvas.Scale((float)_bodyScaleX, (float)_bodyScaleY);
        DrawBody(canvas, s, palette, variant);
        variant.DrawDecorations(canvas, s, palette);
        canvas.Restore();

        // Eyes and feet are children of mascotNode (not body) — unaffected by body rotation
        DrawEyes(canvas, s, variant, (float)eyeScale, (float)pupilX);
        DrawFeet(canvas, s, palette);

        canvas.Restore();

        // Prop label: drawn in screen space above the mascot
        string prop = Activity.Prop();
        if (!string.IsNullOrEmpty(prop))
            DrawProp(canvas, prop, (float)MascotX + shiftX, groundY - liftY - s, s);
    }

    private static void DrawBody(SKCanvas canvas, float s, MascotColor palette, MascotVariant variant)
    {
        using var path = variant.BodyPath(s);
        using var fill   = new SKPaint { Color = palette.Body, IsAntialias = true };
        using var stroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 115), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1.5f,
        };
        canvas.DrawPath(path, fill);
        canvas.DrawPath(path, stroke);
    }

    private static void DrawEyes(SKCanvas canvas, float s, MascotVariant variant,
                                  float eyeScaleY, float pupilOffsetX)
    {
        float eyeR   = s * 0.12f;
        float pupilR = eyeR * 0.55f;
        float eyeY   = variant.EyeY(s);

        using var eyeFill   = new SKPaint { Color = SKColors.White, IsAntialias = true };
        using var eyeStroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 153), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };
        using var pupilFill = new SKPaint { Color = SKColors.Black, IsAntialias = true };

        foreach (float ex in new[] { -s * 0.2f, s * 0.2f })
        {
            canvas.Save();
            canvas.Translate(ex, eyeY);
            canvas.Scale(1f, eyeScaleY);
            canvas.DrawCircle(0, 0, eyeR, eyeFill);
            canvas.DrawCircle(0, 0, eyeR, eyeStroke);
            canvas.Restore();

            float px = ex + pupilR * 0.3f + pupilOffsetX;
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
        float lY = _leftFootUp  ? 4f : 0f;
        float rY = !_leftFootUp ? 4f : 0f;

        using var fill   = new SKPaint { Color = palette.Foot, IsAntialias = true };
        using var stroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 128), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };
        PutFoot(canvas, -s * 0.2f, lY, footW, footH, fill, stroke);
        PutFoot(canvas,  s * 0.2f, rY, footW, footH, fill, stroke);
    }

    private static void PutFoot(SKCanvas c, float fx, float oy,
        float fw, float fh, SKPaint fill, SKPaint stroke)
    {
        var r = new SKRect(fx - fw/2, oy - fh, fx + fw/2, oy);
        c.DrawRoundRect(r, fh/2, fh/2, fill);
        c.DrawRoundRect(r, fh/2, fh/2, stroke);
    }

    private static readonly SKTypeface EmojiTypeface =
        SKTypeface.FromFamilyName("Segoe UI Emoji") ?? SKTypeface.Default;

    private static void DrawProp(SKCanvas canvas, string prop,
        float cx, float bodyTopY, float s)
    {
        float y = bodyTopY - s * 0.15f;
        using var font  = new SKFont(EmojiTypeface, s * 0.5f);
        using var paint = new SKPaint { IsAntialias = true, TextAlign = SKTextAlign.Center };
        canvas.DrawText(prop, cx, y, font, paint);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Hit-test helper for OverlayWindow click-through
    // ═════════════════════════════════════════════════════════════════════════

    public (double left, double top, double right, double bottom) MascotBounds()
    {
        double s = MascotSize;
        double cx = MascotX + _danceXOff;
        double lift = _jumpOffset + _bobOffset + _danceYOff;
        return (cx - s/2, GroundY + lift, cx + s/2, GroundY + lift + s);
    }
}
