# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

```bash
./build.sh                  # swift build -c release + assemble build/Claudario.app
CONFIG=debug ./build.sh     # debug build (faster compile, slower runtime)
swift build                 # raw SwiftPM build, no .app bundle (Sources only)
open build/Claudario.app    # launch — menu bar icon appears, no Dock icon
killall Claudario && open build/Claudario.app   # relaunch to pick up code changes
```

There is **no test target**. `swift test` will fail. Verification is manual via the menu bar's `Test: Walk + Jump` / `Test: Notify` items, or by piping mock JSON to `~/.claudario/hook` (see README "Verifying the hook is wired up"). For UI behavior changes (mascot animations, gestures, overlay positioning) you must run the app and observe — type checking alone won't catch visual regressions.

The repo has zero external dependencies. `Package.swift` declares only the `Claudario` executable target; `build.sh` does the swift build, then assembles `.app` by copying the binary, `Info.plist.template`, and `claudario-hook` into the bundle and ad-hoc codesigning it.

## Architecture

Claudario is a menu-bar-only macOS app (`LSUIElement = true`) that renders an interactive mascot in a transparent, click-through overlay window pinned to the Dock area. It receives events from Claude Code via a tiny localhost HTTP bridge.

```
Claude Code → ~/.claudario/hook (bash, curl, 1s timeout, "|| true")
            → POST 127.0.0.1:<port>/event (loopback NWListener)
            → EventServer parses HTTP/1.1 by hand
            → EventRouter (per-session_id state machine)
            → callbacks → MascotScene (SpriteKit) + SoundPlayer
```

The hook script (`claudario-hook` in the repo, installed to `~/.claudario/hook` by `HookInstaller`) is intentionally trivial: it must **never block Claude Code**. Non-zero `PreToolUse` exits would block tool use, so the script always returns 0 (`|| true`) and times out fast (`-m 1`). Don't add logic there — extend the app instead.

### Two state axes on the mascot

`MascotScene` carries two orthogonal state values:

- **`MascotState`** (`idle`, `walking`, `controlled`, `playing`) — top-level mode. Hooks drive `idle ↔ walking`. Clicking the mascot enters `controlled`. `g` from controlled launches `playing` (the dino game in `DinoGame.swift`).
- **`MascotActivity`** (10 cases incl. `idle`/`thinking`/`coding`/…) — orthogonal sub-mode driving prop emoji + decoration animations. Set from `tool_name` via `MascotActivity.category(forTool:)` on `PreToolUse`.

Hook arrival during `playing` is **buffered**, not applied — the dino game wins, and `applyPendingClaudeState()` replays the latest Claude state when the player exits via Esc. Hook arrival during `controlled` preempts immediately (Claude wins).

### Overlay window & click-through

`OverlayWindow` is borderless, transparent, at `popUpMenuWindow` level, sized 2× the Dock height for jump/prop headroom. `OverlayWindowController.updateClickThrough()` runs **every frame** (via `MascotScene.onTick`) and toggles `window.ignoresMouseEvents` based on whether the cursor is inside the mascot's bounding rect. This is what makes the rest of the strip click-through to the Dock while clicks on the mascot still register.

Two consequences worth knowing:

- `mouseMoved` events are not delivered when the window ignores mouse events. Anything that needs continuous cursor tracking (e.g. the petting gesture detector) must **poll `NSEvent.mouseLocation`** rather than rely on tracking areas. The pattern is: pass a `() -> CGPoint?` closure into the scene that converts screen → window → SKView coords. See `mouseLocationProvider` wiring in `OverlayWindowController.rebuild()`.
- `InteractiveContentView.hitTest` returns `nil` while `state == .walking` so clicks pass through; clicks only register when `idle`/`controlled`/`playing`.

### Per-frame writes vs. SKActions

`MascotScene` mixes two animation styles, and they fight each other if you don't keep them apart:

- **Activity decorations** (`applyActivityDecoration`) drive `body`/`leftEye`/`rightEye`/`leftPupil`/`rightPupil`/`mascotNode` via `SKAction`s with named keys (`bodySquashKey`, `eyeActionKey`, `pupilActionKey`, `decorationActionKey`).
- **Continuous reactions** (`tickPetting` / `applyPettingReaction`) write `yScale` / `zRotation` directly each frame.

If you add another continuous reaction, gate it on `currentActivity == .idle` (or remove the conflicting actions on engage and re-call `applyActivityDecoration()` on release) — otherwise the per-frame writes and `SKAction`s will visibly thrash. See `tickPetting` for the engage/release pattern.

### Variants and decorations are rebuilt on every change

`MascotVariant.buildDecorations(into:size:palette:)` is called from `rebuildMascot()`, `setColor()`, and `setVariant()`. Each call does `decorationNode.removeAllChildren()` first — so any node added via `buildDecorations` does not survive a color/variant/size cycle. If a feature needs to find a decoration node later, name it (`node.name = "..."`) and re-locate via `decorationNode.childNode(withName:)`; do not cache references that outlive a rebuild.

### Settings persistence

`MascotSettings` wraps `UserDefaults` for size, color index, and variant index. Cycling helpers (`cycleColor`, `cycleVariant`, `nudgeSize`) return the new value and persist as a side effect; the keymap in `OverlayWindowController` calls these on `c`/`v`/`,`/`.` and feeds the result back into the scene.

## Editing conventions specific to this repo

- Match existing comment style: explain *why*, not *what*. The codebase already follows this — don't add explanatory headers, don't write docstrings for private helpers.
- The `MascotActivity` enum order is load-bearing: number-row keys `1`…`0` map to `MascotActivity.allCases[0…9]` in `OverlayWindowController.activityKeys`. Reordering cases silently breaks the keyboard preview.
- `EventServer` is hand-rolled HTTP — only enough to find `Content-Length` and read the body. Don't replace it with a dependency; that's a deliberate choice (see README "HTTP protocol on the wire").
- The `idle` activity is **not** motionless — it runs blink + glance `SKAction`s. Don't treat `currentActivity == .idle` as "no animations on the eyes/pupils."
