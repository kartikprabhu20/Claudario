using SkiaSharp;

namespace Claudario.Windows.Mascot;

/// <summary>
/// Phase 0-1: draws a static circle mascot.
/// State/activity stubs are wired to EventRouter callbacks;
/// Phase 2 replaces Draw() with full walking/animating rendering.
/// </summary>
public class MascotScene
{
    public const double GroundY = 4; // pixels from bottom of strip

    public double MascotSize { get; } = 44;
    public double MascotX    { get; private set; }  // center-x in scene coords

    public MascotState    State    { get; private set; } = MascotState.Idle;
    public MascotActivity Activity { get; private set; } = MascotActivity.Idle;

    // Celebrate/Notify animation: mascotY offset applied in Draw()
    private double _jumpOffset;
    private System.Timers.Timer? _animTimer;

    private int _colorIndex = 0;

    // --- State machine (Phase 1 stubs, full implementation in Phase 2) ---

    public void SetState(MascotState state)
    {
        State = state;
        System.Diagnostics.Debug.WriteLine($"MascotScene.SetState → {state}");
    }

    public void SetActivity(MascotActivity activity)
    {
        Activity = activity;
        System.Diagnostics.Debug.WriteLine($"MascotScene.SetActivity → {activity}  prop={activity.Prop()}");
    }

    public void Celebrate()
    {
        // Quick jump: +36 then back — visible confirmation hook fired
        RunJump(amplitude: 36, bounces: 1);
    }

    public void Notify()
    {
        // Small double-bounce
        RunJump(amplitude: 14, bounces: 2);
    }

    private void RunJump(double amplitude, int bounces)
    {
        _animTimer?.Stop();
        _animTimer?.Dispose();

        int step = 0;
        int totalSteps = bounces * 4; // up / peak / down / land per bounce
        double interval = 50;         // ms per step

        _animTimer = new System.Timers.Timer(interval);
        _animTimer.Elapsed += (_, _) =>
        {
            double t = (step % 4) / 3.0;
            // Simple triangle wave: up on steps 0-1, down on steps 2-3
            _jumpOffset = step % 4 < 2
                ? amplitude * (step % 4 + 1) / 2.0
                : amplitude * (4 - step % 4) / 2.0;

            step++;
            if (step >= totalSteps)
            {
                _jumpOffset = 0;
                _animTimer?.Stop();
            }
        };
        _animTimer.AutoReset = true;
        _animTimer.Start();
    }

    // --- Drawing ---

    public void Draw(SKCanvas canvas, int pixelWidth, int pixelHeight)
    {
        canvas.Clear(SKColors.Transparent);

        if (MascotX == 0) MascotX = pixelWidth * 0.1;

        var palette = MascotPalette.Colors[_colorIndex];
        float s  = (float)MascotSize;
        float cx = (float)MascotX;
        // Y=0 at bottom in scene coords; Y=0 at top in canvas coords
        float cy = pixelHeight - (float)GroundY - s / 2f - (float)_jumpOffset;

        // Body
        using var bodyPaint = new SKPaint
            { Color = palette.Body, IsAntialias = true, Style = SKPaintStyle.Fill };
        canvas.DrawCircle(cx, cy, s / 2f, bodyPaint);

        using var outlinePaint = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 115), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1.5f,
        };
        canvas.DrawCircle(cx, cy, s / 2f, outlinePaint);

        // Eyes
        float eyeR   = s * 0.12f;
        float pupilR = eyeR * 0.55f;
        float eyeY   = cy - s * 0.12f;

        using var eyePaint   = new SKPaint { Color = SKColors.White, IsAntialias = true };
        using var pupilPaint = new SKPaint { Color = SKColors.Black, IsAntialias = true };
        using var eyeOutline = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 153), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };

        foreach (float ex in new[] { cx - s * 0.2f, cx + s * 0.2f })
        {
            canvas.DrawCircle(ex, eyeY, eyeR, eyePaint);
            canvas.DrawCircle(ex, eyeY, eyeR, eyeOutline);
            canvas.DrawCircle(ex + pupilR * 0.3f, eyeY, pupilR, pupilPaint);
        }

        // Feet
        float footW = s * 0.28f, footH = s * 0.14f;
        float footY = pixelHeight - (float)GroundY;

        using var footPaint   = new SKPaint { Color = palette.Foot, IsAntialias = true };
        using var footOutline = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 128), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };

        foreach (float fx in new[] { cx - s * 0.2f, cx + s * 0.2f })
        {
            var footRect = new SKRect(fx - footW / 2, footY - footH, fx + footW / 2, footY);
            canvas.DrawRoundRect(footRect, footH / 2, footH / 2, footPaint);
            canvas.DrawRoundRect(footRect, footH / 2, footH / 2, footOutline);
        }

        // Activity prop label above head
        string prop = Activity.Prop();
        if (!string.IsNullOrEmpty(prop))
        {
            using var font = new SKFont(SKTypeface.Default, s * 0.5f);
            using var propPaint = new SKPaint { IsAntialias = true, TextAlign = SKTextAlign.Center };
            canvas.DrawText(prop, cx, cy - s * 0.85f, font, propPaint);
        }
    }
}
