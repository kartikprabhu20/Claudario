using System.IO;
using System.Net;

namespace Claudario.Windows.Server;

public sealed class EventServer : IDisposable
{
    private const int PreferredPort = 47821;

    private readonly EventRouter _router;
    private HttpListener?        _listener;
    private CancellationTokenSource? _cts;

    public int Port { get; private set; }

    public EventServer(EventRouter router) => _router = router;

    public void Start(Action<int> onReady)
    {
        // Try preferred port first, fall back to OS-assigned.
        int port = TryBind(PreferredPort) ?? TryBind(0) ?? -1;
        if (port < 0)
        {
            System.Diagnostics.Debug.WriteLine("Claudario: could not bind any port");
            return;
        }
        Port = port;

        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claudario");
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "port"), port.ToString());

        _cts = new CancellationTokenSource();
        var token = _cts.Token;
        Task.Run(() => AcceptLoop(token), token);

        onReady(port);
    }

    private int? TryBind(int port)
    {
        try
        {
            var lis = new HttpListener();
            string prefix = port == 0
                ? $"http://127.0.0.1:{FreeTcpPort()}/"
                : $"http://127.0.0.1:{port}/";
            lis.Prefixes.Add(prefix);
            lis.Start();
            _listener = lis;

            // Extract actual port from the prefix we registered
            var uri  = new Uri(prefix);
            return uri.Port;
        }
        catch
        {
            return null;
        }
    }

    private static int FreeTcpPort()
    {
        using var sock = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        sock.Start();
        int p = ((IPEndPoint)sock.LocalEndpoint).Port;
        sock.Stop();
        return p;
    }

    private async Task AcceptLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            HttpListenerContext ctx;
            try { ctx = await _listener!.GetContextAsync(); }
            catch { break; }

            _ = Task.Run(() => HandleRequest(ctx), token);
        }
    }

    private void HandleRequest(HttpListenerContext ctx)
    {
        try
        {
            using var ms = new MemoryStream();
            ctx.Request.InputStream.CopyTo(ms);
            var body = ms.ToArray();

            if (body.Length > 0)
                _router.Handle(body);

            ctx.Response.StatusCode = 204;
            ctx.Response.Close();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Claudario: request error: {ex.Message}");
            try { ctx.Response.Abort(); } catch { }
        }
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _listener?.Stop();
        _listener?.Close();
    }
}
