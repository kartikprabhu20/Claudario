using SkiaSharp;

namespace Claudario.Windows.Mascot;

public enum MascotVariant { Classic, Egg, Cat, Dog, Owl, Panda, Robot }

public static class MascotVariantExtensions
{
    // Body silhouette in mascot-local space: X centered on 0, Y=0 at bottom, Y=s at top.
    // Callers apply a canvas transform (Translate + Scale(±1,-1)) before drawing.
    public static SKPath BodyPath(this MascotVariant v, float s)
    {
        var path = new SKPath();
        switch (v)
        {
            case MascotVariant.Classic:
                path.AddRoundRect(new SKRect(-s / 2, 0, s / 2, s), s * 0.3f, s * 0.3f);
                break;

            case MascotVariant.Egg:
            {
                float bottomR = s * 0.45f, topR = s * 0.32f, waistY = s * 0.42f;
                path.MoveTo(0, 0);
                path.CubicTo(bottomR * 0.9f, 0, bottomR, waistY * 0.4f, bottomR, waistY);
                path.CubicTo(bottomR, waistY + (s - waistY) * 0.35f, topR * 0.9f, s, 0, s);
                path.CubicTo(-topR * 0.9f, s, -bottomR, waistY + (s - waistY) * 0.35f, -bottomR, waistY);
                path.CubicTo(-bottomR, waistY * 0.4f, -bottomR * 0.9f, 0, 0, 0);
                path.Close();
                break;
            }

            case MascotVariant.Cat:
            {
                float corner = s * 0.18f, bodyTop = s * 0.70f;
                path.MoveTo(-s / 2 + corner, 0);
                path.QuadTo(-s / 2, 0, -s / 2, corner);
                path.LineTo(-s / 2, bodyTop);
                path.LineTo(-s * 0.30f, s * 1.05f);   // left ear tip
                path.LineTo(-s * 0.10f, bodyTop);
                path.LineTo( s * 0.10f, bodyTop);
                path.LineTo( s * 0.30f, s * 1.05f);   // right ear tip
                path.LineTo( s / 2, bodyTop);
                path.LineTo( s / 2, corner);
                path.QuadTo(s / 2, 0, s / 2 - corner, 0);
                path.Close();
                break;
            }

            case MascotVariant.Dog:
            {
                float corner = s * 0.18f, bodyTop = s * 0.85f;
                path.MoveTo(-s / 2 + corner, 0);
                path.QuadTo(-s / 2, 0, -s / 2, corner);
                path.LineTo(-s / 2, s * 0.20f);
                // left floppy ear
                path.QuadTo(-s * 0.60f, s * 0.10f, -s * 0.62f, s * 0.22f);
                path.QuadTo(-s * 0.74f, s * 0.40f, -s * 0.62f, s * 0.55f);
                path.QuadTo(-s * 0.55f, s * 0.66f, -s / 2, s * 0.65f);
                path.LineTo(-s / 2, bodyTop - corner);
                path.QuadTo(-s / 2, bodyTop, -s / 2 + corner, bodyTop);
                path.LineTo(s / 2 - corner, bodyTop);
                path.QuadTo(s / 2, bodyTop, s / 2, bodyTop - corner);
                path.LineTo(s / 2, s * 0.65f);
                // right floppy ear
                path.QuadTo(s * 0.55f, s * 0.66f, s * 0.62f, s * 0.55f);
                path.QuadTo(s * 0.74f, s * 0.40f, s * 0.62f, s * 0.22f);
                path.QuadTo(s * 0.60f, s * 0.10f, s / 2, s * 0.20f);
                path.LineTo(s / 2, corner);
                path.QuadTo(s / 2, 0, s / 2 - corner, 0);
                path.Close();
                break;
            }

            case MascotVariant.Owl:
                path.MoveTo(0, 0);
                path.QuadTo(s * 0.52f, 0, s * 0.48f, s * 0.40f);
                path.QuadTo(s * 0.55f, s * 0.68f, s * 0.40f, s * 0.85f);
                path.LineTo( s * 0.32f, s * 1.05f);   // right tuft
                path.LineTo( s * 0.18f, s * 0.92f);
                path.QuadTo(0, s * 0.84f, -s * 0.18f, s * 0.92f);
                path.LineTo(-s * 0.32f, s * 1.05f);   // left tuft
                path.LineTo(-s * 0.40f, s * 0.85f);
                path.QuadTo(-s * 0.55f, s * 0.68f, -s * 0.48f, s * 0.40f);
                path.QuadTo(-s * 0.52f, 0, 0, 0);
                path.Close();
                break;

            case MascotVariant.Panda:
                path.AddOval(new SKRect(-s * 0.50f, 0, s * 0.50f, s * 0.92f));
                break;

            case MascotVariant.Robot:
            {
                float corner = s * 0.06f, bodyTop = s * 0.85f;
                float stemHW = s * 0.06f, stemTop = s * 0.98f;
                path.MoveTo(-s / 2 + corner, 0);
                path.QuadTo(-s / 2, 0, -s / 2, corner);
                path.LineTo(-s / 2, bodyTop - corner);
                path.QuadTo(-s / 2, bodyTop, -s / 2 + corner, bodyTop);
                path.LineTo(-stemHW, bodyTop);
                path.LineTo(-stemHW, stemTop);
                path.LineTo( stemHW, stemTop);
                path.LineTo( stemHW, bodyTop);
                path.LineTo(s / 2 - corner, bodyTop);
                path.QuadTo(s / 2, bodyTop, s / 2, bodyTop - corner);
                path.LineTo(s / 2, corner);
                path.QuadTo(s / 2, 0, s / 2 - corner, 0);
                path.Close();
                break;
            }
        }
        return path;
    }

    // Eye center Y in mascot-local space (Y=0 at bottom).
    public static float EyeY(this MascotVariant v, float s) => v switch
    {
        MascotVariant.Classic => s * 0.70f,
        MascotVariant.Egg     => s * 0.62f,
        MascotVariant.Cat     => s * 0.45f,
        MascotVariant.Dog     => s * 0.55f,
        MascotVariant.Owl     => s * 0.55f,
        MascotVariant.Panda   => s * 0.55f,
        MascotVariant.Robot   => s * 0.55f,
        _                     => s * 0.60f,
    };

    // Draw variant decorations on canvas. Canvas is already transformed into
    // mascot-local space (X centered, Y=0 at bottom, Y up = positive).
    public static void DrawDecorations(this MascotVariant v, SKCanvas canvas, float s, MascotColor palette)
    {
        switch (v)
        {
            case MascotVariant.Cat:   DrawCatDecorations(canvas, s);           break;
            case MascotVariant.Dog:   DrawDogDecorations(canvas, s, palette);  break;
            case MascotVariant.Owl:   DrawOwlDecorations(canvas, s);           break;
            case MascotVariant.Panda: DrawPandaDecorations(canvas, s);         break;
            case MascotVariant.Robot: DrawRobotDecorations(canvas, s);         break;
        }
    }

    private static void DrawCatDecorations(SKCanvas canvas, float s)
    {
        var pink    = new SKColor(255, 184, 199, 217);
        var whisker = new SKColor(0, 0, 0, 115);

        // Inner ear triangles
        using var earPaint = new SKPaint { Color = pink, IsAntialias = true };
        foreach (float sign in new[] { -1f, 1f })
        {
            using var p = new SKPath();
            p.MoveTo(sign * s * 0.40f, s * 0.74f);
            p.LineTo(sign * s * 0.30f, s * 0.97f);
            p.LineTo(sign * s * 0.16f, s * 0.74f);
            p.Close();
            canvas.DrawPath(p, earPaint);
        }

        // Nose
        using var nosePaint = new SKPaint { Color = new SKColor(0, 0, 0, 166), IsAntialias = true };
        using var np = new SKPath();
        np.MoveTo(-s * 0.05f, s * 0.34f);
        np.LineTo( s * 0.05f, s * 0.34f);
        np.LineTo(0,           s * 0.27f);
        np.Close();
        canvas.DrawPath(np, nosePaint);

        // Whiskers: 3 per side with slight droop
        float[] ys    = { s * 0.32f, s * 0.30f, s * 0.27f };
        float[] droops = { s * 0.01f, 0,         -s * 0.015f };
        using var wPaint = new SKPaint
        {
            Color = whisker, IsAntialias = true,
            Style = SKPaintStyle.Stroke,
            StrokeWidth = Math.Max(1f, s * 0.025f),
            StrokeCap = SKStrokeCap.Round,
        };
        foreach (float sign in new[] { -1f, 1f })
            for (int i = 0; i < 3; i++)
            {
                using var lp = new SKPath();
                lp.MoveTo(sign * s * 0.10f, ys[i]);
                lp.LineTo(sign * s * 0.42f, ys[i] + droops[i]);
                canvas.DrawPath(lp, wPaint);
            }
    }

    private static void DrawDogDecorations(SKCanvas canvas, float s, MascotColor palette)
    {
        // Snout lobes in foot color
        using var snoutPaint = new SKPaint { Color = palette.Foot, IsAntialias = true };
        foreach (float sign in new[] { -1f, 1f })
        {
            float cx = sign * s * 0.13f, cy = s * 0.22f;
            canvas.DrawOval(cx, cy, s * 0.17f, s * 0.18f, snoutPaint);
        }

        // Black nose
        using var nosePaint = new SKPaint { Color = new SKColor(0, 0, 0, 166), IsAntialias = true };
        canvas.DrawOval(0, s * 0.34f, s * 0.09f, s * 0.065f, nosePaint);

        // Pink tongue
        using var tonguePaint = new SKPaint { Color = new SKColor(237, 46, 56, 255), IsAntialias = true };
        using var tp = new SKPath();
        tp.MoveTo(-s * 0.07f, s * 0.22f);
        tp.QuadTo(0, s * 0.02f, s * 0.07f, s * 0.22f);
        tp.Close();
        canvas.DrawPath(tp, tonguePaint);
        using var tongueStroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 64), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 0.8f,
        };
        canvas.DrawPath(tp, tongueStroke);
    }

    private static void DrawOwlDecorations(SKCanvas canvas, float s)
    {
        // Facial disks
        using var diskPaint = new SKPaint { Color = new SKColor(0, 0, 0, 51), IsAntialias = true };
        using var diskStroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 77), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };
        foreach (float sign in new[] { -1f, 1f })
        {
            canvas.DrawCircle(sign * s * 0.20f, s * 0.55f, s * 0.18f, diskPaint);
            canvas.DrawCircle(sign * s * 0.20f, s * 0.55f, s * 0.18f, diskStroke);
        }

        // Beak
        using var beakPaint = new SKPaint { Color = new SKColor(242, 166, 51, 255), IsAntialias = true };
        using var bp = new SKPath();
        bp.MoveTo(-s * 0.06f, s * 0.45f);
        bp.LineTo( s * 0.06f, s * 0.45f);
        bp.LineTo(0,           s * 0.32f);
        bp.Close();
        canvas.DrawPath(bp, beakPaint);
        using var beakStroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 102), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 0.8f,
        };
        canvas.DrawPath(bp, beakStroke);
    }

    private static void DrawPandaDecorations(SKCanvas canvas, float s)
    {
        var black = new SKColor(0, 0, 0, 217);

        // Ears
        using var earPaint = new SKPaint { Color = black, IsAntialias = true };
        foreach (float sign in new[] { -1f, 1f })
            canvas.DrawCircle(sign * s * 0.30f, s * 0.85f, s * 0.18f, earPaint);

        // Eye patches (rotated ovals)
        using var patchPaint = new SKPaint { Color = black, IsAntialias = true };
        foreach (float sign in new[] { -1f, 1f })
        {
            canvas.Save();
            canvas.Translate(sign * s * 0.20f, s * 0.55f);
            canvas.RotateRadians(sign * 0.20f);
            canvas.DrawOval(0, 0, s * 0.11f, s * 0.15f, patchPaint);
            canvas.Restore();
        }

        // Nose
        using var nosePaint = new SKPaint { Color = black, IsAntialias = true };
        canvas.DrawOval(0, s * 0.32f, s * 0.07f, s * 0.05f, nosePaint);

        // Mouth connector + smile
        float lw = Math.Max(1.2f, s * 0.035f);
        using var mouthPaint = new SKPaint
        {
            Color = black, IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = lw, StrokeCap = SKStrokeCap.Round,
        };
        using var conn = new SKPath();
        conn.MoveTo(0, s * 0.27f); conn.LineTo(0, s * 0.20f);
        canvas.DrawPath(conn, mouthPaint);

        using var smile = new SKPath();
        smile.MoveTo(-s * 0.08f, s * 0.20f);
        smile.QuadTo(0, s * 0.12f, s * 0.08f, s * 0.20f);
        canvas.DrawPath(smile, mouthPaint);
    }

    private static void DrawRobotDecorations(SKCanvas canvas, float s)
    {
        var metalDark = new SKColor(0, 0, 0, 140);

        // Antenna bulb
        using var bulbPaint = new SKPaint { Color = new SKColor(255, 64, 77, 255), IsAntialias = true };
        using var bulbStroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 128), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };
        canvas.DrawCircle(0, s * 1.06f, s * 0.08f, bulbPaint);
        canvas.DrawCircle(0, s * 1.06f, s * 0.08f, bulbStroke);

        // Visor
        using var visorPaint = new SKPaint { Color = new SKColor(0, 0, 0, 140), IsAntialias = true };
        canvas.DrawRoundRect(new SKRect(-s*0.34f, s*0.42f, s*0.34f, s*0.68f), s*0.05f, s*0.05f, visorPaint);
        using var visorStroke = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 102), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f,
        };
        canvas.DrawRoundRect(new SKRect(-s*0.34f, s*0.42f, s*0.34f, s*0.68f), s*0.05f, s*0.05f, visorStroke);

        // Mouth grille
        using var mouthPaint = new SKPaint { Color = metalDark, IsAntialias = true };
        canvas.DrawRoundRect(new SKRect(-s*0.14f, s*0.20f, s*0.14f, s*0.28f), s*0.015f, s*0.015f, mouthPaint);
        using var grillePaint = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 178), IsAntialias = true,
            Style = SKPaintStyle.Stroke, StrokeWidth = Math.Max(0.8f, s * 0.018f),
            StrokeCap = SKStrokeCap.Round,
        };
        foreach (int i in new[] { -1, 0, 1 })
        {
            float x = i * s * 0.06f;
            using var bar = new SKPath();
            bar.MoveTo(x, s * 0.215f); bar.LineTo(x, s * 0.265f);
            canvas.DrawPath(bar, grillePaint);
        }

        // Corner bolts
        using var boltPaint = new SKPaint { Color = metalDark, IsAntialias = true };
        (float bx, float by)[] bolts = {
            (-s*0.40f, s*0.10f), (s*0.40f, s*0.10f),
            (-s*0.40f, s*0.75f), (s*0.40f, s*0.75f),
        };
        foreach (var (bx, by) in bolts)
            canvas.DrawCircle(bx, by, s * 0.04f, boltPaint);
    }
}
