using SkiaSharp;
using Claudario.Windows.Settings;

namespace Claudario.Windows.Mascot;

/// <summary>
/// Side-scrolling minigame data and logic. No SpriteKit node tree —
/// all state is plain fields; rendering is done via Draw() onto the
/// same SKCanvas that MascotScene uses, with the mascot drawn by
/// MascotScene.DrawPlayingMode on top.
/// </summary>
public sealed class DinoGame
{
    private const float JumpVelocity = 600f;
    private const float GravityMag   = 1800f;

    private struct Obstacle { public float Left, Width, Height; }
    private readonly List<Obstacle> _obstacles = new();

    private readonly float          _mascotSize;
    private readonly MascotColor    _palette;
    private readonly MascotSettings _settings;

    // Physics in canvas Y-down pixels. groundY = canvas Y of feet at rest.
    // _playerY starts at groundY; decreases (goes up on screen) when airborne.
    private float    _playerY;
    private float    _groundY;
    private float    _vertVelocity;   // positive = downward in canvas
    private float    _scrollSpeed;
    private float    _spawnAccum;
    private float    _nextSpawnInterval;
    private DateTime _lastTick = DateTime.MinValue;

    public float MascotGameX { get; private set; }
    public float MascotGameY => _playerY;  // canvas Y of mascot bottom
    public int   Score       { get; private set; }
    public bool  IsOver      { get; private set; }

    private static readonly SKTypeface HudTypeface =
        SKTypeface.FromFamilyName("Consolas")
        ?? SKTypeface.FromFamilyName("Courier New")
        ?? SKTypeface.Default;

    public DinoGame(float mascotSize, MascotColor palette, MascotSettings settings)
    {
        _mascotSize = mascotSize;
        _palette    = palette;
        _settings   = settings;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public void Start(float groundY)
    {
        _groundY           = groundY;
        _playerY           = groundY;
        MascotGameX        = _mascotSize / 2 + 24;
        _vertVelocity      = 0;
        _scrollSpeed       = 240;
        _nextSpawnInterval = 1.6f;
        _spawnAccum        = 0;
        Score              = 0;
        IsOver             = false;
        _lastTick          = DateTime.MinValue;
        _obstacles.Clear();
    }

    // ── Input ─────────────────────────────────────────────────────────────────

    public void Jump()
    {
        if (IsOver) return;
        // Allow jump only when standing on the ground.
        if (_playerY < _groundY - 0.5f || _vertVelocity != 0) return;
        _vertVelocity = -JumpVelocity;
    }

    public void Restart()
    {
        if (!IsOver) return;
        _obstacles.Clear();
        _playerY      = _groundY;
        _vertVelocity = 0;
        IsOver        = false;
        Score         = 0;
        _scrollSpeed       = 240;
        _nextSpawnInterval = 1.6f;
        _spawnAccum        = 0;
        _lastTick          = DateTime.MinValue;
    }

    // ── Tick ──────────────────────────────────────────────────────────────────

    public void Tick(float sceneWidth)
    {
        var now = DateTime.UtcNow;
        float dt;
        if (_lastTick == DateTime.MinValue) dt = 1f / 60f;
        else dt = (float)Math.Min((now - _lastTick).TotalSeconds, 1.0 / 30.0);
        _lastTick = now;

        if (IsOver) return;

        // Vertical physics (canvas Y-down: positive velocity = falling)
        _vertVelocity += GravityMag * dt;
        _playerY      += _vertVelocity * dt;
        if (_playerY >= _groundY) { _playerY = _groundY; _vertVelocity = 0; }

        // Spawn obstacles on a shrinking interval that never drops below 0.7 s
        _spawnAccum += dt;
        if (_spawnAccum >= _nextSpawnInterval)
        {
            _spawnAccum = 0;
            SpawnObstacle(sceneWidth);
            float progress = Math.Min((float)Score / 30f, 1f);
            _nextSpawnInterval = 1.6f - 0.9f * progress
                                 + (Random.Shared.NextSingle() * 0.3f - 0.15f);
            _nextSpawnInterval = Math.Max(0.7f, _nextSpawnInterval);
        }

        // Scroll obstacles left; count a point for each that exits the left edge
        float dx = _scrollSpeed * dt;
        for (int i = _obstacles.Count - 1; i >= 0; i--)
        {
            var o = _obstacles[i];
            o.Left -= dx;
            if (o.Left + o.Width < 0)
            {
                _obstacles.RemoveAt(i);
                Score++;
                _settings.SaveDinoHighScore(Score);
            }
            else _obstacles[i] = o;
        }
        _scrollSpeed = Math.Min(420f, 240f + Score * 4f);

        // Collision: slightly inset hitbox (6px horizontal, 4px from bottom)
        float s  = _mascotSize;
        float mL = MascotGameX - s / 2 + 6;
        float mR = MascotGameX + s / 2 - 6;
        float mT = _playerY - (s - 4);  // canvas top (smaller Y = higher on screen)
        float mB = _playerY - 4;        // canvas bottom (4 px above feet)

        foreach (var o in _obstacles)
        {
            float oL = o.Left, oR = o.Left + o.Width;
            float oT = _groundY - o.Height, oB = _groundY;
            if (mL < oR && mR > oL && mT < oB && mB > oT)
            {
                IsOver = true;
                _settings.SaveDinoHighScore(Score);
                return;
            }
        }
    }

    private void SpawnObstacle(float sceneWidth)
    {
        float s      = _mascotSize;
        bool  isTall = Random.Shared.NextSingle() > 0.5f;
        float height = isTall ? s * 0.64f : s * 0.34f;
        float width  = s * 0.32f;
        _obstacles.Add(new Obstacle { Left = sceneWidth, Width = width, Height = height });
    }

    // ── Draw ──────────────────────────────────────────────────────────────────
    // Draws ground line, obstacles, and HUD. The mascot itself is drawn by
    // MascotScene.DrawPlayingMode so it can reuse the shared draw helpers.

    public void Draw(SKCanvas canvas, float sceneWidth, float sceneHeight)
    {
        // Ground line
        using var gp = new SKPaint { Color = _palette.Foot.WithAlpha(102) };
        canvas.DrawRect(0, _groundY, sceneWidth, 1f, gp);

        // Obstacles — rounded rects matching the palette
        using var fill   = new SKPaint { Color = _palette.Body, IsAntialias = true };
        using var stroke = new SKPaint
        {
            Color = _palette.Foot.WithAlpha(153),
            Style = SKPaintStyle.Stroke, StrokeWidth = 1f, IsAntialias = true,
        };
        foreach (var o in _obstacles)
        {
            float radius = Math.Min(o.Width, o.Height) * 0.3f;
            var rect = new SKRect(o.Left, _groundY - o.Height, o.Left + o.Width, _groundY);
            canvas.DrawRoundRect(rect, radius, radius, fill);
            canvas.DrawRoundRect(rect, radius, radius, stroke);
        }

        // Score HUD (right-aligned)
        int    hi        = Math.Max(Score, _settings.DinoHighScore);
        string scoreText = $"SCORE {Score:D3}  HI {hi:D3}";
        using var hudFont  = new SKFont(HudTypeface, 13f);
        using var hudPaint = new SKPaint
        {
            Color = SKColors.White, IsAntialias = true, TextAlign = SKTextAlign.Right,
        };
        canvas.DrawText(scoreText, sceneWidth - 12, _groundY - 8, hudFont, hudPaint);

        // Game-over hint (centred, above midpoint)
        if (IsOver)
        {
            const string hint = "GAME OVER  ·  R restart  ·  Esc exit";
            using var hf = new SKFont(HudTypeface, 12f);
            using var hp = new SKPaint
            {
                Color = SKColors.White, IsAntialias = true, TextAlign = SKTextAlign.Center,
            };
            canvas.DrawText(hint, sceneWidth / 2f, sceneHeight * 0.38f, hf, hp);
        }
    }
}
