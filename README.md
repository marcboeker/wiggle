# Wiggle

<p align="center">
  <img src="docs/app-icon.png" alt="Wiggle app icon" width="128">
</p>

Wiggle is a Dock-less macOS accessory app. Shake the mouse pointer and a wheel of shortcut slots
opens around it; click a slot, or press its key, and it runs a keyboard shortcut, opens an app, or
runs an Apple Shortcut or AppleScript, right where you were working.

## Why Wiggle

- **No hunting for a hotkey** — the wheel opens right where the pointer is.
- **More than one way in** — shake the pointer, bump a screen edge, or tap or swipe the trackpad.
- **25 slots** — a center slot, 8 inner, and 16 outer, the outer ring hidden until assigned.
- **Any kind of action** — a shortcut, an app, an Apple Shortcut, or an AppleScript.
- **Stays out of the way** — no Dock icon, an optional menu bar item, no stolen keyboard focus.
- **Plain JSON config** — one file you can read, edit, or sync yourself.

## Getting Started

macOS 14 (Sonoma) or later. **Install via Homebrew:**

```sh
brew tap marcboeker/wiggle https://github.com/marcboeker/wiggle
brew trust --cask marcboeker/wiggle/wiggle
brew install --cask wiggle
```

The app is ad-hoc signed, so Gatekeeper blocks it the first time you open it — click **Done**, then
open **System Settings → Privacy & Security** and **Open Anyway**, or clear the quarantine flag:
`xattr -dr com.apple.quarantine /Applications/Wiggle.app`.

**Or build it from source:**

```sh
git clone https://github.com/marcboeker/wiggle.git && cd wiggle && make run
```

`make run` builds, ad-hoc signs, and opens `build/Wiggle.app`; see [Build and develop](#build-and-develop) below.

On first launch, macOS asks for **Accessibility** permission to watch the pointer and send
keystrokes; an AppleScript or Apple Shortcut slot also asks for **Automation** permission once.

## Use

| Action | Result |
| --- | --- |
| Shake the pointer | The wheel opens, pinned where the pointer was |
| Bump a screen edge, pull back, and stop | The wheel opens where the pointer stops (switch on in Settings) |
| Tap the trackpad with three or four fingers | The wheel opens at the pointer (switch on in Settings) |
| Swipe up or down with four fingers | The wheel opens when the fingers lift (switch on in Settings) |
| Click a slot, or press its key | Runs the slot |
| Escape, or a click outside the wheel | Closes it |
| Another app comes to the front | Closes it |

The center slot runs on Return, the inner ring on `1`-`8`, and the outer ring on `a`-`p` once
assigned. A menu bar item, on by default, offers **Settings…** (`⌘,`) and **Quit Wiggle** (`⌘Q`);
`⌘,` also opens Settings from the wheel, which has **General**, **Actions**, and **Triggers** pages.

## Configuration

Slots and settings live in `~/.config/wiggle/config.json` (`--config <path>` for another file). An
image face, if a slot has one, is a PNG next to it in `~/.config/wiggle/icons/`.

```json
{
  "overlayOpacity": 0.92,
  "rings": [
    { "0": { "app": { "bundleIdentifier": "com.apple.Terminal", "name": "Terminal" }, "kind": "app" } },
    { "1": { "kind": "shortcut", "label": "📷", "shortcut": "cmd+shift+4" } },
    {}
  ],
  "triggers": ["wiggle"]
}
```

`rings` holds one object per ring (center, inner, outer) keyed by slot number, with no key for an
empty slot; `triggers` lists the enabled gestures — without it, only `wiggle` is on.

## Build and develop

| Target | Action |
| --- | --- |
| `make build` | Compile without bundling. |
| `make bundle` | Build, assemble, and sign `build/Wiggle.app`. |
| `make run` | Stop any running copy, bundle, and open it. |
| `make stop` | Quit a running copy. |
| `make test` | Run the unit tests. |
| `make logs` | Stream the app's log messages. |
| `make permissions` | Open Privacy & Security → Accessibility. |
| `make clean` | Remove all build output. |

`SIGN_ID` picks the codesigning identity `make bundle` uses; unset, it auto-detects an Apple
Development identity or falls back to an ad hoc signature (`-`, what CI and a release use).

## Limits

Secure input (password fields, `sudo`, the lock screen) blocks every event tap, so close the wheel
with a click outside there instead of a key. A shortcut macOS already claims, `command`+`space`
for example, is answered by the system and not Wiggle, which posts keys at the hardware level.

## License

MIT, see [LICENSE](LICENSE).
