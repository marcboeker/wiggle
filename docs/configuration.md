# Configuration

Wiggle keeps all slots and settings in one JSON file. You can change everything in Settings, so
you never have to edit the file. Edit it only to sync it between Macs, keep it in a dotfiles
repository, or change many slots at once.

## File location

| Item | Path |
| --- | --- |
| Config file | `~/.config/wiggle/config.json` |
| Image faces | `~/.config/wiggle/icons/` |
| Backup of a broken file | `~/.config/wiggle/config.json.broken` |

To use another file, start the app with `--config <path>`:

```sh
open -a Wiggle --args --config ~/dotfiles/wiggle.json
```

The `icons` folder is always next to the config file. If the config file is a symlink, as a
dotfile manager makes it, Wiggle writes through the link and keeps it.

## Edit the file by hand

- **Quit Wiggle first.** Wiggle reads the file once, at launch. It does not watch the file for
  changes, and it writes the whole file again each time you change something in Settings. An edit
  made while Wiggle runs is lost.
- Wiggle rewrites the file with sorted keys and its own formatting. It drops comments and keys it
  does not know.
- If a value is missing or wrong, Wiggle uses the default for that value and does not fail. See
  [Errors and recovery](#errors-and-recovery).

## Example

```json
{
  "overlayAppearance": "auto",
  "overlayOpacity": 0.92,
  "rings": [
    { "0": { "app": { "bundleIdentifier": "com.apple.Terminal", "name": "Terminal" }, "kind": "app" } },
    {
      "1": { "kind": "shortcut", "label": "📷", "shortcut": "cmd+shift+4", "color": "blue" },
      "2": { "kind": "previousApp" }
    },
    {}
  ],
  "showMenuBarItem": true,
  "triggerShortcut": "cmd+ctrl+alt+shift",
  "triggers": ["wiggle", "shortcut"],
  "version": 4
}
```

## Top-level keys

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `version` | number | `4` | Format version. Wiggle writes `4`. Keep it. |
| `rings` | array of 3 objects | all slots empty | The slots. See [Rings and slots](#rings-and-slots). |
| `triggers` | array of strings | `["wiggle"]` | The gestures that open the wheel. See [Triggers](#triggers). |
| `triggerShortcut` | string | `"cmd+ctrl+alt+shift"` | The key combination for the `shortcut` trigger. See [Shortcut spelling](#shortcut-spelling). |
| `overlayOpacity` | number | `0.92` | How see-through the wheel is. `0.5` to `1`. A value outside the range is set to the nearest limit. |
| `overlayAppearance` | string | `"auto"` | `"light"`, `"dark"`, or `"auto"`, which follows the system. |
| `showMenuBarItem` | boolean | `true` | Show the menu bar item. If it is off, open Wiggle.app again to open Settings. |

All keys except `version` and `rings` are optional.

## Rings and slots

`rings` has three objects: the center, the inner ring, and the outer ring, in this order. Each
object maps a slot number, written as a string, to a slot. An empty slot has no key.

| Ring | Index in `rings` | Slot numbers | Keys in the wheel |
| --- | --- | --- | --- |
| Center | 0 | `0` | Return |
| Inner | 1 | `1` to `8` | `1` to `8` |
| Outer | 2 | `1` to `16` | `a` to `p` |

The outer ring is hidden until at least one of its slots has an assignment. Slots in a ring count
clockwise. Slot 1 of the inner ring is centered on the top; slot 1 of the outer ring sits just left of
the top and ends at it. A slot number outside these ranges is ignored.

### Slot keys

Every slot has a `kind`. The other keys depend on the kind.

| Key | Used by | Meaning |
| --- | --- | --- |
| `kind` | all | The action. See [Action kinds](#action-kinds). Required. |
| `color` | all | Optional. The slot tint: `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, or `pink`. An unknown name means no color. |
| `label` | `shortcut`, `appleShortcut`, `appleScript` | The emoji on the slot. Only the first character is used. |
| `shortcut` | `shortcut` | The key combination to send. |
| `app` | `app` | The app, as `{ "bundleIdentifier": "...", "name": "..." }`. |
| `appleShortcut` | `appleShortcut` | The shortcut, as `{ "name": "..." }`. |
| `script` | `appleScript` | The AppleScript source text. |

`label` is the key for the emoji, for historical reasons. An `app` slot and a `previousApp` slot
show an app icon and have no `label`.

### Action kinds

| `kind` | What it does | Extra keys |
| --- | --- | --- |
| `shortcut` | Sends a key combination to the app in front. | `shortcut`, `label` |
| `app` | Opens an app, or brings it to the front. | `app` |
| `previousApp` | Brings the app you used before the front app back to the front. | none |
| `appleShortcut` | Runs a shortcut from the Shortcuts app by name, with `/usr/bin/shortcuts run`. | `appleShortcut`, `label` |
| `appleScript` | Runs an AppleScript with `/usr/bin/osascript`. The script goes in over standard input, so it can have many lines. | `script`, `label` |

Examples of each kind:

```json
{ "kind": "shortcut", "label": "📷", "shortcut": "cmd+shift+4" }
{ "kind": "app", "app": { "bundleIdentifier": "com.apple.Terminal", "name": "Terminal" } }
{ "kind": "previousApp" }
{ "kind": "appleShortcut", "label": "🌙", "appleShortcut": { "name": "Toggle Dark Mode" } }
{ "kind": "appleScript", "label": "🧀", "script": "display alert \"Cheese, please!\"" }
```

An app is stored by bundle identifier, so the slot still works after the app moves. Find the
identifier of an installed app with `osascript -e 'id of app "Terminal"'`.

### Image faces

A slot can show a PNG image and not an emoji. The image is not in the JSON file. Wiggle stores
it in `~/.config/wiggle/icons/` and finds it by the slot name:

| Slot | File name |
| --- | --- |
| Center | `center.png` |
| Inner slot 1 to 8 | `slot-1.png` to `slot-8.png` |
| Outer slot a to p | `slot-a.png` to `slot-p.png` |

If a slot has an image file, the image wins over `label`. To set an image face by hand, put a PNG
with the right name in the folder. Wiggle deletes a PNG that belongs to an empty slot or to an
`app` or `previousApp` slot the next time it saves. Wiggle scales images it creates to at most
256 pixels on the long side.

## Triggers

`triggers` lists the gestures that open the wheel. It must name at least one known gesture. If it
is missing, empty, or has only unknown names, Wiggle uses `["wiggle"]`. Wiggle skips a name it
does not know, so a file from a newer version still loads.

| Name | Gesture |
| --- | --- |
| `wiggle` | Shake the pointer. |
| `screenEdge` | Push the pointer against a screen edge, pull back, and stop. |
| `threeFingerTap` | Tap the trackpad with three fingers. |
| `fourFingerTap` | Tap the trackpad with four fingers. |
| `fourFingerSwipeUp` | Swipe up with four fingers. |
| `fourFingerSwipeDown` | Swipe down with four fingers. |
| `shortcut` | Hold the key combination in `triggerShortcut`. The wheel closes when you let go. |
| `middleMouseButton` | Press the middle mouse button, the one under the scroll wheel. |

`triggerShortcut` matters only when `triggers` has `shortcut`. A trigger shortcut is one of:

- Modifiers only, for example `cmd+ctrl+alt+shift` (the Hyper key). At least one modifier is
  needed. The wheel shows while you hold the keys.
- A key with at least one of `cmd`, `ctrl`, or `alt`, for example `ctrl+alt+space`.
- A function key, `f1` to `f20`, alone or with modifiers.

A key alone, or a key with only `shift`, is not allowed, because it would take keys from normal
typing. If the value is not allowed or not valid, Wiggle uses `cmd+ctrl+alt+shift`.

## Shortcut spelling

A shortcut is a string of modifiers and one key, joined with `+`, for example `cmd+shift+4`.

- **Modifiers:** `cmd` (or `command`), `ctrl` (or `control`), `alt` (or `option`), and `shift`.
  Their order does not matter. Case does not matter. Wiggle writes them as `cmd`, `ctrl`, `alt`,
  `shift`, in this order.
- **Key:** one key name. A slot shortcut needs a key. A trigger shortcut can have only modifiers.
- Key names are fixed physical keys, not the letters of your keyboard layout. A saved shortcut
  means the same key on every Mac.

| Keys | Names |
| --- | --- |
| Letters | `a` to `z` |
| Digits | `0` to `9` |
| Function keys | `f1` to `f20` |
| Editing | `return`, `tab`, `space`, `delete`, `forwarddelete`, `escape`, `help` |
| Navigation | `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown` |
| Punctuation | `backslash`, `backtick`, `comma`, `equal`, `minus`, `period`, `quote`, `semicolon`, `slash`, `leftbracket`, `rightbracket` |
| Any other key | `keycodeN`, where `N` is the macOS virtual key code, for example `keycode10` |

A shortcut that macOS already claims, such as `cmd+space`, is answered by the system. Wiggle
posts keys at the hardware level and cannot replace that.

## Errors and recovery

Wiggle does not stop on a bad file. It has these rules:

| Problem | What Wiggle does |
| --- | --- |
| A slot cannot be read, for example a typo in `shortcut` | Empties that slot, keeps the other slots, and saves a copy of the original file as `config.json.broken`. |
| A value has an unknown name (trigger, color, appearance) | Skips it and uses the default. |
| A key is missing | Uses the default. |
| The whole file is not valid JSON or does not match the format | Moves the file to `config.json.broken` and starts with an empty configuration. |

`config.json.broken` holds your previous content, so you can fix it and copy your slots back.
Wiggle writes the message that names the problem to the system log. Stream it with:

```sh
log stream --predicate 'eventMessage CONTAINS "wiggle:"'
```

Older files of versions 1 to 3 are read once and saved in the current format at the next change.
