# Claudario — Windows 10+ porting plan

> Status: **planning only**. No Windows code has been written yet. This
> document is the architectural roadmap so a future implementer (human
> or AI agent) can execute the port in independently-shippable phases.
> The macOS app under `Sources/` is unaffected.

## 1. Overview & non-goals

**Goal**: feature parity with the macOS app on Windows 10 (build 1809+)
and Windows 11. Same mascot, same activities, same hook integration,
same tray menu, same dino-runner, same petting gesture.

**Non-goals**:
- Cross-compiling from macOS — the Windows build runs on Windows.
- Sharing source between platforms — separate project, intentional code
  duplication for the small (~2K LOC) surface.
- UWP / Microsoft Store packaging — desktop `.exe` only, side-loaded.
- Multi-monitor rendering — match the macOS app's `NSScreen.main` limit.

## 2. Tech stack

| Concern                | Choice                                       | Rationale                                                                  |
| ---------------------- | -------------------------------------------- | -------------------------------------------------------------------------- |
| Language / runtime     | **C# / .NET 8**                              | LTS; single-file self-contained `.exe`; modern JSON & sockets in BCL.      |
| UI framework           | **WPF**                                      | Native support for transparent topmost click-through windows on Win10/11.   |
| 2D drawing             | **SkiaSharp**                                | `SKPath` is the closest thing to `CGPath`; `MascotVariant.bodyPath` ports almost line-for-line. |
| System tray            | **Hardcodet.NotifyIcon.Wpf**                 | Functional `NSStatusItem` equivalent; MIT-licensed; no `System.Windows.Forms` dependency. |
| Loopback HTTP          | **`System.Net.HttpListener`** (BCL)          | Drop-in for `NWListener`; same protocol on the wire.                       |
| JSON                   | **`System.Text.Json`** (BCL, `JsonNode`)     | Same merge-and-back-up shape as `JSONSerialization` in `HookInstaller`.    |
| Settings persistence   | **Registry under `HKCU\Software\Claudario`** | Replaces `UserDefaults`; small set of scalar keys.                         |
| Audio                  | **`System.Media.SoundPlayer`**                | Plays `.wav` files from `C:\Windows\Media\` — Windows analogue of `/System/Library/Sounds/`. |
| Hook bridge            | **`claudario-hook.cmd`** (batch)             | Calls `curl.exe` (built into Win10 1803+); same trivial 1-second-timeout, never-fail design as the macOS bash version. |
| Build                  | **`dotnet publish` via `build.ps1`**         | `-c Release -r win-x64 --self-contained -p:PublishSingleFile=true`.        |

### Why not the alternatives

- **C++/Win32/Direct2D** — feasible but ~3–4× the LOC for the same overlay + tray logic, with no payoff vs. C#/WPF on modern Windows.
- **Electron / Tauri** — ships a browser engine for a 50 KB mascot.
- **WinUI 3** — still has rough edges around always-on-top transparent overlay windows on Win10. WPF's behavior is well-trodden.
- **Rust + winit + tiny-skia** — modern and clean, but tray + transparent click-through windowing are less mature in the Rust ecosystem.

## 3. File-by-file mapping

| macOS source                                  | Windows equivalent                                                                                  | Effort   |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------- | -------- |
| `main.swift`                                  | `App.xaml` + `App.xaml.cs`                                                                          | Trivial  |
| `AppDelegate.swift`                           | `App.OnStartup` — wires server → router → scene → tray → installer, same callback graph             | Easy     |
| `Overlay/DockGeometry.swift`                  | `Overlay/TaskbarGeometry.cs` — `SHAppBarMessage(ABM_GETTASKBARPOS)` + `GetMonitorInfo`              | Easy     |
| `Overlay/OverlayWindow.swift`                 | `Overlay/OverlayWindow.xaml(.cs)` — transparent topmost; `SetWindowLong` toggles `WS_EX_TRANSPARENT`/`WS_EX_NOACTIVATE` | Tricky |
| `Overlay/OverlayWindowController.swift`       | `Overlay/OverlayController.cs` — same per-frame `updateClickThrough` loop, `GetCursorPos` instead of `NSEvent.mouseLocation` | Easy |
| `Overlay/InteractiveContentView.swift`        | Mouse / key handlers on `OverlayWindow`; sub-region hit-testing via the same flag toggle           | Easy     |
| `Mascot/MascotState.swift`                    | `Mascot/MascotState.cs` enum                                                                        | Trivial  |
| `Mascot/MascotActivity.swift`                 | `Mascot/MascotActivity.cs` enum + tool→activity map                                                 | Trivial  |
| `Mascot/MascotPalette.swift`                  | `Mascot/MascotPalette.cs` static array                                                              | Trivial  |
| `Mascot/MascotVariant.swift`                  | `Mascot/MascotVariant.cs` — `SKPath` builds, identical coords                                       | Easy     |
| `Mascot/MascotScene.swift`                    | `Mascot/MascotScene.cs` — per-frame tick from `CompositionTarget.Rendering`; `SKAction`s become time-driven property writes | Medium |
| `Mascot/DinoGame.swift`                       | `Mascot/DinoGame.cs` — pure logic, port 1:1                                                          | Easy     |
| `Server/EventServer.swift`                    | `Server/EventServer.cs` — `HttpListener` on `http://127.0.0.1:<port>/`                              | Trivial  |
| `Server/EventRouter.swift`                    | `Server/EventRouter.cs` — pure state machine                                                         | Trivial  |
| `Settings/MascotSettings.swift`               | `Settings/MascotSettings.cs` — registry-backed `HKCU\Software\Claudario`                            | Easy     |
| `Audio/SoundPlayer.swift`                     | `Audio/SoundPlayer.cs` — `tada.wav` for coin, `chord.wav` for notify                                | Easy     |
| `MenuBar/StatusItemController.swift`          | `Tray/TrayController.cs` — Hardcodet.NotifyIcon.Wpf, same menu, same callbacks                      | Easy     |
| `Install/HookInstaller.swift`                 | `Install/HookInstaller.cs` — same JSON merge against `%USERPROFILE%\.claude\settings.json`, with timestamped backup | Easy |
| `claudario-hook` (bash)                       | `claudario-hook.cmd` (batch) — `curl.exe -m 1 -s -X POST … 2>NUL`                                   | Trivial  |
| `Info.plist.template`                         | `app.manifest` — `<dpiAware>True/PM</dpiAware>`, `<requestedExecutionLevel level="asInvoker"/>`     | Easy     |
| `build.sh`                                    | `build.ps1` — `dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true`     | Easy     |

The ports marked **Trivial** / **Easy** are mostly transcription. The two
nontrivial ones (`OverlayWindow`, `MascotScene`) are addressed below.

## 4. Tricky bits worth calling out

### Click-through transparent overlay
WPF gets you transparency for free (`AllowsTransparency=true`,
`WindowStyle=None`, `Background=Transparent`, `Topmost=true`,
`ShowInTaskbar=false`). For the dynamic per-frame click-through pattern
that the macOS app uses (`ignoresMouseEvents` toggled based on cursor
proximity), `[DllImport("user32")] SetWindowLong(hwnd, GWL_EXSTYLE, …)`
flips the `WS_EX_TRANSPARENT` bit in the same per-frame loop. Same
architecture; different syscall.

### No `mouseMoved` events on a click-through window
Same constraint as macOS. The petting gesture detector already polls
the cursor — on Windows it polls `GetCursorPos` from the per-frame
tick. Pattern transfers without redesign.

### Topmost above the taskbar
`Topmost=true` is enough on Win10/11 — the taskbar is not z-order locked.
Full-screen apps demote other windows automatically, mirroring the macOS
`popUpMenuWindow` level behavior.

### DPI scaling
Declare `<dpiAware>True/PM</dpiAware>` in `app.manifest`. SkiaSharp
surface size scales by `DpiX/DpiY`. Test 100% / 150% / 200% — this
is the most common source of Windows mascot bugs.

### Taskbar autohide and edge changes
Parallel to Dock autohide. Re-query `SHAppBarMessage` on
`WM_SETTINGCHANGE` and `ABN_POSCHANGED`; recompute the overlay
position. (macOS uses `NSWorkspace.activeSpaceDidChangeNotification`
+ Dock pref-changed broadcast for the same purpose.)

### Hook script registration on Windows
Claude Code's `hooks[].command` field accepts any shell command. The
Windows hook command will be:

```
cmd.exe /c "%USERPROFILE%\.claudario\hook.cmd"
```

This needs a one-line validation against current Claude Code on
Windows before Phase 1 commits to the design. If `cmd.exe /c …` does
not work, fall back to a PowerShell `.ps1` invocation with
`-ExecutionPolicy Bypass`.

### Code signing / SmartScreen
Ad-hoc unsigned binaries trigger SmartScreen on first run. For dev
builds, use a self-signed cert via `New-SelfSignedCertificate` +
`signtool`. For production, a real Authenticode cert. Document both
paths in `windows/README.md` when it's written.

## 5. Folder layout

Today (after this work item):

```
windows/
└── PORTING_PLAN.md
```

After future Phase 0 (scaffolding):

```
windows/
├── PORTING_PLAN.md
├── README.md
├── Claudario.Windows.sln
├── Claudario.Windows/
│   ├── Claudario.Windows.csproj
│   ├── App.xaml / App.xaml.cs
│   ├── app.manifest
│   ├── Overlay/         { OverlayWindow.xaml(.cs), OverlayController.cs, TaskbarGeometry.cs }
│   ├── Mascot/          { MascotScene.cs, MascotVariant.cs, MascotActivity.cs, MascotState.cs,
│   │                      MascotPalette.cs, DinoGame.cs }
│   ├── Server/          { EventServer.cs, EventRouter.cs }
│   ├── Settings/        { MascotSettings.cs }
│   ├── Audio/           { SoundPlayer.cs }
│   ├── Tray/            { TrayController.cs }
│   └── Install/         { HookInstaller.cs }
├── claudario-hook.cmd
└── build.ps1
```

## 6. Phased implementation plan

Each phase is independently shippable — stopping after any phase yields
something a user can launch and verify.

| Phase | Deliverable                                                                                   | Verifiable by                                                                                          |
| ----- | --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **0** | Solution + csproj scaffold; tray icon visible; transparent overlay window draws a static circle on the taskbar | Launch the exe → tray icon appears → circle pinned to the bottom of the screen                          |
| **1** | `EventServer` + `EventRouter` + `notify()` / `celebrate()` stub anims; `claudario-hook.cmd` works end-to-end | `Invoke-WebRequest -Uri http://127.0.0.1:47821/event -Method Post -Body '{"hook_event_name":"Stop"}'` triggers the celebration animation |
| **2** | Full `MascotVariant` + `MascotScene` rendering (idle blink/glance, walking)                   | Mascot blinks and walks back and forth across the strip                                                |
| **3** | All 10 activity decorations (`thinking` / `coding` / … / `dancing`)                           | Number-row `1`–`0` in interactive mode previews each animation (depends on Phase 4)                    |
| **4** | Interactive mode: click-to-control, keyboard handler, walking under arrow keys, jump          | Click the mascot → drive with `←` / `→` / `↑` / `Esc`                                                  |
| **5** | Petting gesture + dino-runner game                                                            | Wag the cursor over the head → squint + sway. Press `g` → game starts                                 |
| **6** | `HookInstaller` (JSON merge into `%USERPROFILE%\.claude\settings.json`); Launch-at-Login (`HKCU\…\Run`); sound mapping | Tray menu's *Install Claude Code Hooks* succeeds; running `claude` in a real terminal triggers walks/jumps |

Phase 1 alone proves hooks integrate. Phase 2 alone is a watchable
mascot. Phase 6 reaches parity.

## 7. Risks & open questions

- **Claude Code on Windows hook-command format** — confirm `cmd.exe /c …` is accepted by current Claude Code on Windows; one-line `claude --help` test required before Phase 1.
- **WPF + SkiaSharp 60 FPS render tearing on a transparent topmost window** — historically smooth, but worth a 5-min spike in Phase 0.
- **`HttpListener` URL ACL registration** — binding to `http://127.0.0.1:<port>/` typically does not require admin, but document the `netsh http add urlacl` fallback in case it does on locked-down hosts.
- **AV/EDR products may flag an unsigned exe that listens on a port** — self-signing + a one-line note in `windows/README.md` covers most cases.
- **Windows 10 build floor** — `curl.exe` is built in since 1803 (April 2018). For older builds, the hook script needs PowerShell `Invoke-RestMethod` instead. Document the floor.

## 8. What this document is NOT

- **Not** a code dump. No C# source is committed alongside this `.md`.
- **Not** a build artifact. No solution, csproj, or NuGet packages.
- **Not** a commitment to ship. The user reviews this doc and decides whether the port is worth the implementation token spend.

---

*Last updated: planning session 2026-05-08. macOS app revision: see
`git log Sources/` for the most recent change baseline.*
