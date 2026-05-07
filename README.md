# Claudario

A small mascot that walks above your Dock while Claude Code is working.
It jumps with a chime when a turn finishes and bounces with a different
tone when Claude needs your attention (permission prompts, follow-up
questions, idle reminders).
---

## Table of contents

1. [What you get](#what-you-get)
2. [Requirements](#requirements)
3. [Build & first run](#build--first-run)
4. [Setting up Claude Code integration](#setting-up-claude-code-integration)
5. [Making it default for every Claude session](#making-it-default-for-every-claude-session)
6. [Architecture](#architecture)
7. [How it connects to Claude Code (hooks)](#how-it-connects-to-claude-code-hooks)
8. [Event → animation state machine](#event--animation-state-machine)
9. [HTTP protocol on the wire](#http-protocol-on-the-wire)
10. [File / directory layout](#file--directory-layout)
11. [Security model](#security-model)
12. [Customization](#customization)
13. [Troubleshooting](#troubleshooting)
14. [Uninstall](#uninstall)
15. [Limitations](#limitations)

---

## What you get

- Menu-bar app (no Dock icon — `LSUIElement = true`).
- Transparent, click-through overlay window pinned to the Dock area.
- Procedurally-drawn mascot:
  - **Idle** when no Claude session is active.
  - **Walks back and forth** while Claude is processing.
  - **Jumps + chime** (`Glass`) when Claude finishes a turn.
  - **Bounces + tone** (`Funk`) when Claude needs permission or asks a
    question.
- Auto-recomputes its position when the Dock is moved, hidden, or you
  switch Spaces / displays.
- Loopback-only HTTP server (not reachable off-host).
- One-click install / uninstall of Claude Code hooks (with backup of
  your existing `settings.json`).
- Optional Launch-at-Login.

---

## Requirements

- **macOS 13** (Ventura) or newer (`SMAppService` and modern `Network`
  framework features).
- **Swift 5.9+** / Xcode 15+ command line tools (`xcode-select --install`
  is enough — no Xcode app needed to build).
- **Claude Code** installed (`npm i -g @anthropic-ai/claude-code` or
  whichever installation method you use).

---

## Build & first run

```bash
git clone <this-repo> Claudario
cd Claudario
./build.sh
open build/Claudario.app
```

You should see:

1. A small orange square (`🟧`) appear in the menu bar (top right of
   your screen).
2. A small mascot at the bottom of your main display, sitting on top
   of (or in the area of) the Dock.

Click the menu-bar icon to get the menu:

```
Enabled                              ✓
Launch at Login
─────────────────────────────────
Install Claude Code Hooks
Uninstall Claude Code Hooks
─────────────────────────────────
Test: Walk + Jump
Test: Notify
─────────────────────────────────
About Claudario
─────────────────────────────────
Quit
```

Try **Test: Walk + Jump** first — the mascot should walk for ~4 seconds
and then jump with a chime. **Test: Notify** does the bounce + tone.
This verifies the renderer and audio path before you wire up Claude Code.

---

## Setting up Claude Code integration

There are two pieces:

1. **The app must be running.** Either launch it manually
   (`open build/Claudario.app`) or enable **Launch at Login** from the
   menu so it starts automatically whenever you log in.
2. **Claude Code hooks must be installed** into your settings file.
   This is done once. Click **Install Claude Code Hooks** from the menu.

That's it. Open a new terminal, run `claude` in any directory, ask it to
do something multi-step (e.g. *"add a function and run the tests"*) and
the mascot will walk while Claude works, bounce when it asks for tool
permission, and jump when it finishes.

### What "Install Claude Code Hooks" actually does

It's a non-destructive merge into `~/.claude/settings.json`:

1. Copies the bundled hook script into `~/.claudario/hook`
   (a 7-line bash file that just `curl`s the hook payload to the running
   app).
2. If `~/.claude/settings.json` already exists, writes a timestamped
   backup next to it (e.g. `settings.json.bak.1715079600`).
3. Adds (or updates) entries under the `hooks` key for these events:
   `UserPromptSubmit`, `PreToolUse`, `Stop`, `SubagentStop`,
   `Notification`, `SessionStart`, `SessionEnd`. Existing entries you
   already have are kept.
4. If a previous Claudario entry exists, it's deduplicated, not
   appended (safe to click "Install" multiple times).

The injected entry looks like this:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "/Users/you/.claudario/hook" }
        ]
      }
    ]
    // ... same shape for the other six events
  }
}
```

### Verifying the hook is wired up

```bash
# Confirm the script is there:
cat ~/.claudario/hook

# Confirm settings.json contains your hook command:
grep claudario ~/.claude/settings.json

# End-to-end: run the hook script directly and watch the mascot:
echo '{"hook_event_name":"UserPromptSubmit","session_id":"manual"}' \
  | ~/.claudario/hook
# Mascot should start walking.

echo '{"hook_event_name":"Stop","session_id":"manual"}' \
  | ~/.claudario/hook
# Mascot should jump + chime.
```

---

## Making it default for every Claude session

Claude Code reads hooks from three locations in order, with later
overriding earlier:

| Scope          | File                            | Applies to                         |
| -------------- | ------------------------------- | ---------------------------------- |
| User (global)  | `~/.claude/settings.json`       | **Every** Claude session you run   |
| Project        | `<project>/.claude/settings.json` | Only sessions in that project      |
| Project local  | `<project>/.claude/settings.local.json` | That project, machine-local |

**Claudario installs into the user-global file** (`~/.claude/settings.json`),
so once you click **Install Claude Code Hooks**, every Claude Code
session — in any directory, on any project, on this machine — fires the
hooks.

Combined with **Launch at Login**, that gives you a fully default
setup:

1. **Menu → Launch at Login** ✓ (so the app starts on every login)
2. **Menu → Install Claude Code Hooks** ✓ (so every `claude` session
   fires events)

After that, you can forget about it — it just works whenever you open
a new terminal and type `claude`.

> If you want to **disable** Claudario for a specific project (e.g.
> noisy CI scripts running `claude` in headless mode), drop a small
> `.claude/settings.local.json` in that project that sets the same hook
> events to an empty array. Project-local settings override user
> settings.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Claude Code  (CLI process you run in a terminal)                    │
│                                                                      │
│   reads ~/.claude/settings.json on launch ──► hooks block            │
│                                                                      │
│   on each event, spawns:                                             │
│     /bin/bash ~/.claudario/hook  <stdin: JSON payload>               │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         │  stdin: { "hook_event_name": "...",
                         │           "session_id": "...", ... }
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ ~/.claudario/hook  (7 lines of bash)                                 │
│                                                                      │
│   PORT=$(cat ~/.claudario/port || echo 47821)                        │
│   curl -m 1 -s -X POST --data-binary @-                              │
│        http://127.0.0.1:$PORT/event   || true                        │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         │  HTTP POST /event
                         │  { "hook_event_name": "...", ... }
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Claudario.app                                                        │
│                                                                      │
│   ┌──────────────┐     ┌─────────────┐    ┌────────────────────────┐ │
│   │ EventServer  ├────►│ EventRouter ├───►│ MascotScene (SpriteKit)│ │
│   │ NWListener   │     │ state by    │    │  walking / idle /      │ │
│   │ loopback:port│     │ session_id  │    │  jump / bounce         │ │
│   └──────────────┘     └─────────────┘    └────────────────────────┘ │
│                                              │                        │
│                                              ▼                        │
│                                        OverlayWindow                  │
│                                        (transparent, click-through,   │
│                                         level=popUpMenu, above Dock)  │
│                                                                       │
│   ┌──────────────┐                                                   │
│   │ SoundPlayer  │   plays NSSound("Glass")  on coin                 │
│   │              │   plays NSSound("Funk")   on notify               │
│   └──────────────┘                                                   │
│                                                                       │
│   ┌─────────────────────┐    ┌─────────────────────┐                 │
│   │ StatusItemController│    │ HookInstaller       │                 │
│   │ (menu bar UI)       │    │ (patches            │                 │
│   │                     │    │  ~/.claude/         │                 │
│   │                     │    │  settings.json)     │                 │
│   └─────────────────────┘    └─────────────────────┘                 │
└──────────────────────────────────────────────────────────────────────┘
```

### Modules and responsibilities

| Source file                              | Job                                                                                  |
| ---------------------------------------- | ------------------------------------------------------------------------------------ |
| `main.swift`                             | Bootstraps NSApplication as `.accessory` and installs `AppDelegate`.                 |
| `AppDelegate.swift`                      | Creates the overlay, server, router, sound player, menu bar; wires their callbacks. |
| `Overlay/DockGeometry.swift`             | Reads `com.apple.dock` defaults + `NSScreen` to compute where the Dock lives.        |
| `Overlay/OverlayWindow.swift`            | Borderless transparent click-through `NSWindow` at `popUpMenu` level.                |
| `Overlay/OverlayWindowController.swift`  | Re-positions the window on screen / Space / Dock-pref changes.                       |
| `Mascot/MascotState.swift`               | `enum MascotState { idle, walking }`.                                                |
| `Mascot/MascotScene.swift`               | SpriteKit scene; draws the mascot procedurally; runs walk/jump/bounce actions.       |
| `Server/EventServer.swift`               | NWListener bound to `.loopback`, parses minimal HTTP/1.1 POSTs.                      |
| `Server/EventRouter.swift`               | Per-`session_id` state machine that maps events to mascot transitions.               |
| `Audio/SoundPlayer.swift`                | One-line wrapper around `NSSound(named:)`.                                           |
| `MenuBar/StatusItemController.swift`     | Menu-bar `NSStatusItem` and its menu (toggles, install/uninstall, tests).            |
| `Install/HookInstaller.swift`            | JSON merge into `~/.claude/settings.json`, with backup and uninstall.                |

---

## How it connects to Claude Code (hooks)

Claude Code provides a [hooks
system](https://docs.claude.com/en/docs/claude-code/hooks-guide) that
fires on key lifecycle events. Each registered hook can spawn an
arbitrary shell command and feeds it a JSON payload on stdin.

The events Claudario subscribes to:

| Hook event         | Fires when…                                                              | Used for          |
| ------------------ | ------------------------------------------------------------------------ | ----------------- |
| `SessionStart`     | A `claude` process starts a new session                                  | Track session ID  |
| `UserPromptSubmit` | You submit a prompt                                                      | Start walking     |
| `PreToolUse`       | Before each tool call (Read, Bash, Edit, …)                              | Keep walking      |
| `PostToolUse`      | After each tool call                                                     | Refresh activity  |
| `Notification`     | Permission prompts, AskUserQuestion follow-ups, idle reminders           | Bounce + tone     |
| `Stop`             | Claude finishes a top-level turn                                         | Jump + chime      |
| `SubagentStop`     | A spawned subagent finishes                                              | Jump + chime      |
| `SessionEnd`       | The session terminates                                                   | Clear state       |

The JSON payload Claude Code sends includes (at minimum)
`hook_event_name`, `session_id`, `transcript_path`, and `cwd`. We only
look at `hook_event_name` and `session_id` — the rest is ignored but
available for future features.

### Why a single bash script for every event

The hook script (`~/.claudario/hook`) is intentionally trivial:

```bash
#!/bin/bash
PORT_FILE="$HOME/.claudario/port"
PORT="$(cat "$PORT_FILE" 2>/dev/null || echo 47821)"
exec curl -s -m 1 -X POST \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "http://127.0.0.1:$PORT/event" >/dev/null 2>&1 || true
```

Properties that matter:

- **`-m 1`** — 1-second timeout. If the app is closed, missing, or
  unresponsive, the hook returns within 1 s.
- **`|| true`** — non-zero exit codes from `curl` are swallowed.
  Critically, `PreToolUse` hooks that return non-zero **block tool
  use** in Claude Code; we never want a stale Claudario instance to
  get in your way.
- **`>/dev/null 2>&1`** — silent. No noise in your terminal.
- **No state in the script** — the app holds all logic. The script
  is interchangeable.

### Why a port file

The HTTP server tries port `47821` first; if that's already in use, it
falls back to a random ephemeral port assigned by the kernel. Whatever
port it ends up on is written to `~/.claudario/port` so the bash hook
can find it without a complicated discovery protocol.

---

## Event → animation state machine

`EventRouter` keeps a dictionary keyed by `session_id`:

```swift
struct SessionState { var isWalking: Bool; var lastSeen: Date }
var sessions: [String: SessionState] = [:]
```

Transitions:

| Event                             | Effect on `sessions[id]`        | Mascot side-effect                                        |
| --------------------------------- | ------------------------------- | --------------------------------------------------------- |
| `SessionStart`                    | create entry, `isWalking=false` | none                                                      |
| `UserPromptSubmit`, `PreToolUse`  | `isWalking=true`                | If no session was walking before → call `onWalk()`        |
| `PostToolUse`                     | refresh `lastSeen`              | none                                                      |
| `Notification`                    | refresh `lastSeen`               | `onNotify()` (does not change walk state)                 |
| `Stop`, `SubagentStop`            | `isWalking=false`                | If no session is still walking → `onIdle()` + `onCelebrate()` |
| `SessionEnd`                      | remove entry                    | If no session is still walking → `onIdle()`               |

Sessions idle for >5 min are auto-evicted to handle the case where
`SessionEnd` doesn't fire (e.g. the user `kill`s the Claude process).

Concurrent sessions are handled correctly: walking persists as long as
**at least one** session is in flight. The celebration only fires when
**all** sessions have stopped.

---

## HTTP protocol on the wire

The smallest thing that could possibly work:

- **Method**: `POST` (any path; we don't even check it).
- **Body**: the JSON payload Claude Code piped to the hook script.
- **Response**: `204 No Content`.

```
POST /event HTTP/1.1
Host: 127.0.0.1:47821
Content-Type: application/json
Content-Length: 79

{"hook_event_name":"UserPromptSubmit","session_id":"abc","cwd":"/Users/me/x"}
```

```
HTTP/1.1 204 No Content
Content-Length: 0
Connection: close
```

The server is hand-rolled in `EventServer.swift` — about 90 lines —
because pulling in a dependency for "POST one JSON blob and reply 204"
felt absurd. It only handles enough HTTP/1.1 to find the
`Content-Length` header and read the body.

---

## File / directory layout

### In your home directory

```
~/.claudario/
├── port                # plain-text decimal port number
└── hook                # bash bridge installed by HookInstaller

~/.claude/
├── settings.json                  # your Claude Code config (we patch this)
└── settings.json.bak.<timestamp>  # automatic backup before each install
```

### In the repo

```
Claudario/
├── Package.swift              # SwiftPM manifest (no dependencies)
├── Info.plist.template        # Bundle plist (LSUIElement=true, etc.)
├── build.sh                   # swift build → assemble .app bundle
├── claudario-hook             # the bash bridge (gets bundled into .app)
├── README.md
└── Sources/Claudario/
    ├── main.swift
    ├── AppDelegate.swift
    ├── Overlay/
    │   ├── DockGeometry.swift
    │   ├── OverlayWindow.swift
    │   └── OverlayWindowController.swift
    ├── Mascot/
    │   ├── MascotScene.swift
    │   └── MascotState.swift
    ├── Server/
    │   ├── EventServer.swift
    │   └── EventRouter.swift
    ├── Audio/
    │   └── SoundPlayer.swift
    ├── MenuBar/
    │   └── StatusItemController.swift
    └── Install/
        └── HookInstaller.swift
```

### Build outputs

```
.build/release/Claudario        # raw executable (SwiftPM)
build/Claudario.app/            # assembled .app bundle (build.sh output)
    Contents/
    ├── Info.plist
    ├── MacOS/Claudario
    └── Resources/
        └── claudario-hook
```

---

## Security model

- **Loopback-only listener**:
  `params.requiredInterfaceType = .loopback` on the `NWListener`. The
  socket is never bound to a routable interface, so other machines on
  your network cannot reach it.
- **No authentication**: the server accepts any local POST. The
  threat model is essentially "a process running on your machine
  could send events", which is fine — the worst that happens is a
  spurious mascot animation.
- **Read-only outside `~/.claude/settings.json`**: the only files
  Claudario writes to are `~/.claudario/{port,hook}` and the
  `settings.json` patch (with backup).
- **Hook script runs in your shell environment**, just like any
  other Claude Code hook. Its only outbound action is `curl` to
  `127.0.0.1`.
- **No network access** from the app itself: the app neither makes
  outbound HTTP requests nor talks to any cloud service.

---

## Customization

### Sounds

Edit `Sources/Claudario/Audio/SoundPlayer.swift`:

```swift
case .coin:   name = "Glass"   // try "Hero", "Tink", "Submarine"
case .notify: name = "Funk"    // try "Pop", "Blow", "Sosumi"
```

System sounds live at `/System/Library/Sounds/`. To use a custom
file, copy the `.wav` into the app bundle's `Resources/` directory in
`build.sh` and load it with `NSSound(contentsOf:byReference:)`
instead of `NSSound(named:)`.

### Mascot art

`Sources/Claudario/Mascot/MascotScene.swift` builds the mascot from
`SKShapeNode`s. To switch to sprite-sheet art:

1. Drop your PNGs into a `Resources/Mascot.atlas/` folder.
2. Replace `buildMascot()` with `SKSpriteNode(texture:)` plus
   `SKAction.animate(with:timePerFrame:)` for the walk cycle.
3. In `build.sh`, copy the atlas folder into the bundle's
   `Resources/`.

### Walk speed / mascot size

Top of `MascotScene.swift`:

```swift
private let mascotSize: CGFloat = 44     // points
private let walkSpeed: CGFloat = 110     // points / second
```

### Window level

If you want the mascot to render *behind* full-screen windows (so it
disappears when you full-screen something), drop the level in
`OverlayWindow.swift` from `popUpMenuWindow` to `floatingWindow`.

---

## Troubleshooting

### I don't see the mascot

1. Confirm the app is running: `pgrep -fl Claudario`.
2. Confirm the menu-bar icon is there (top-right corner).
3. From the menu, click **Test: Walk + Jump**. If you don't see
   anything, the overlay window is the problem (level / position).
4. If the Dock is on the left or right, v1 falls back to a fixed
   80 pt strip along the bottom — the mascot is there, not next to
   the Dock.

### Hooks don't fire when I run `claude`

```bash
# 1. Is the bridge installed?
ls -l ~/.claudario/hook

# 2. Are the entries in settings.json?
grep -c claudario ~/.claude/settings.json
# Should print 7 (one per registered event).

# 3. Does the script work standalone?
echo '{"hook_event_name":"Stop","session_id":"x"}' | ~/.claudario/hook
# Mascot should jump.

# 4. Is the app actually listening?
lsof -nP -iTCP:47821 -sTCP:LISTEN
```

If `~/.claude/settings.json` exists but doesn't contain Claudario
entries, click **Install Claude Code Hooks** again. If that fails,
the JSON may be malformed — check for trailing commas.

### `Permission denied` when `~/.claudario/hook` runs

The installer sets mode `0755`. If you copied the file by hand:
`chmod +x ~/.claudario/hook`.

### Port 47821 is already in use

The server falls back to an ephemeral port and writes the new value
to `~/.claudario/port`. The hook script reads that file, so this is
transparent. If you want a fixed port, change `preferredPort` in
`AppDelegate.applicationDidFinishLaunching`.

### "Launch at Login" toggle does nothing

`SMAppService.mainApp.register()` requires the app to be in
`/Applications` (or another standard location) and properly signed.
For an ad-hoc dev build in `build/`, register may fail silently.
Move the `.app` to `/Applications` and try again, or just launch
manually for now.

---

## Uninstall

1. Menu bar → **Uninstall Claude Code Hooks** (removes our entries
   from `~/.claude/settings.json`; your other hooks are untouched).
2. Menu bar → **Quit**.
3. (Optional cleanup) `rm -rf ~/.claudario build/Claudario.app`.

Backups of `settings.json` taken at install time remain at
`~/.claude/settings.json.bak.<timestamp>` until you delete them.

---

## Limitations

- **Main screen only** — multi-monitor support is on the to-do list.
  The window pins to `NSScreen.main`.
- **Side-Dock fallback** — if your Dock is on the left or right,
  Claudario draws on a fixed 80 pt bottom strip rather than next to
  the Dock.
- **Procedural art** — the mascot is drawn with `SKShapeNode`s, not
  sprite-sheet pixel art. Easy to replace; see
  [Customization](#customization).
- **No preferences UI** — speed, color, sounds, and window level are
  hardcoded constants. PRs welcome.
- **macOS 13+** because of `SMAppService`. Backporting to 12 would
  require a `LaunchAgent`-based login launcher.
