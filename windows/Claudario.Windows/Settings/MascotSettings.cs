using Microsoft.Win32;

namespace Claudario.Windows.Settings;

/// <summary>
/// Persists mascot preferences to HKCU\Software\Claudario.
/// Port of macOS MascotSettings (UserDefaults → Registry).
/// </summary>
public sealed class MascotSettings
{
    private const string RegPath = @"SOFTWARE\Claudario";

    public static readonly int   DefaultSize       = 44;
    public static readonly int   DefaultColorIndex = 0;
    public static readonly int   DefaultVariantIndex = 0;
    // 24, 32, 40, 48, 56, 64, 72, 80, 88 — 8-px steps matching macOS sizeRange
    public static readonly int[] SizeRange = [24, 32, 40, 48, 56, 64, 72, 80, 88];

    public int Size          { get; private set; }
    public int ColorIndex    { get; private set; }
    public int VariantIndex  { get; private set; }
    public int DinoHighScore { get; private set; }

    public MascotSettings() => Load();

    // Fired on the UI thread whenever color or variant changes.
    public event Action? AppearanceChanged;

    public int CycleColor()
    {
        ColorIndex = (ColorIndex + 1) % 10;
        Save("ColorIndex", ColorIndex);
        AppearanceChanged?.Invoke();
        return ColorIndex;
    }

    public int CycleVariant()
    {
        VariantIndex = (VariantIndex + 1) % 7;
        Save("VariantIndex", VariantIndex);
        AppearanceChanged?.Invoke();
        return VariantIndex;
    }

    // delta > 0 = grow, delta < 0 = shrink; clamps at range edges
    public int NudgeSize(int delta)
    {
        int idx = Array.IndexOf(SizeRange, Size);
        if (idx < 0) idx = Array.IndexOf(SizeRange, DefaultSize);
        idx  = Math.Clamp(idx + (delta > 0 ? 1 : -1), 0, SizeRange.Length - 1);
        Size = SizeRange[idx];
        Save("SizePoints", Size);
        return Size;
    }

    public void SaveDinoHighScore(int score)
    {
        if (score <= DinoHighScore) return;
        DinoHighScore = score;
        Save("DinoHighScore", score);
    }

    private void Load()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegPath);
        Size          = ReadInt(key, "SizePoints",   DefaultSize);
        ColorIndex    = ReadInt(key, "ColorIndex",   DefaultColorIndex);
        VariantIndex  = ReadInt(key, "VariantIndex", DefaultVariantIndex);
        DinoHighScore = ReadInt(key, "DinoHighScore", 0);

        // Clamp in case registry has stale out-of-range values
        if (!SizeRange.Contains(Size)) Size = DefaultSize;
        ColorIndex   = Math.Clamp(ColorIndex,   0, 9);
        VariantIndex = Math.Clamp(VariantIndex, 0, 6);
    }

    private static void Save(string name, int value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RegPath);
        key.SetValue(name, value, RegistryValueKind.DWord);
    }

    private static int ReadInt(RegistryKey? key, string name, int fallback) =>
        key?.GetValue(name) is int v ? v : fallback;
}
