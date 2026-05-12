using SkiaSharp;

namespace Claudario.Windows.Mascot;

public record MascotColor(SKColor Body, SKColor Foot);

public static class MascotPalette
{
    // Matches macOS MascotPalette.swift color order exactly.
    // Index 0 is the default (Anthropic Orange).
    public static readonly MascotColor[] Colors =
    [
        new(SKColor.FromHsl(25,  90, 58), SKColor.FromHsl(25,  80, 42)),  // Anthropic Orange
        new(SKColor.FromHsl(204, 75, 55), SKColor.FromHsl(204, 65, 38)),  // Sky Blue
        new(SKColor.FromHsl(152, 55, 52), SKColor.FromHsl(152, 50, 36)),  // Mint
        new(SKColor.FromHsl(270, 55, 65), SKColor.FromHsl(270, 45, 48)),  // Lavender
        new(SKColor.FromHsl(6,   72, 60), SKColor.FromHsl(6,   62, 44)),  // Coral
        new(SKColor.FromHsl(42,  85, 55), SKColor.FromHsl(42,  75, 38)),  // Mustard
        new(SKColor.FromHsl(340, 65, 65), SKColor.FromHsl(340, 55, 48)),  // Rose
        new(SKColor.FromHsl(178, 58, 48), SKColor.FromHsl(178, 50, 32)),  // Teal
        new(SKColor.FromHsl(25,  40, 40), SKColor.FromHsl(25,  35, 28)),  // Cocoa
        new(SKColor.FromHsl(220, 18, 52), SKColor.FromHsl(220, 15, 36)),  // Slate
    ];
}
