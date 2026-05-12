using System.IO;

namespace Claudario.Windows.Audio;

/// <summary>
/// Plays celebration and notify sounds asynchronously.
/// Each call spawns a short-lived background task so simultaneous
/// sounds can overlap (e.g. rapid hook events) without blocking.
/// </summary>
public static class SoundPlayer
{
    private static readonly string CelebrateFile =
        FindSound("Windows Chimes.wav", "Windows Ding.wav", "chimes.wav");
    private static readonly string NotifyFile =
        FindSound("Windows Notify.wav", "Windows Balloon.wav", "notify.wav");

    public static void PlayCelebrate() => PlayAsync(CelebrateFile);
    public static void PlayNotify()    => PlayAsync(NotifyFile);

    private static void PlayAsync(string path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
        // Capture path in the lambda; PlaySync blocks until done, so the
        // player stays alive for the full duration on this background thread.
        Task.Run(() =>
        {
            try
            {
                using var player = new System.Media.SoundPlayer(path);
                player.PlaySync();
            }
            catch { /* audio failure is non-fatal */ }
        });
    }

    private static string FindSound(params string[] candidates)
    {
        string dir = @"C:\Windows\Media";
        foreach (string name in candidates)
        {
            string full = Path.Combine(dir, name);
            if (File.Exists(full)) return full;
        }
        return string.Empty;
    }
}
