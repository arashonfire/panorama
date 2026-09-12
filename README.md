# Panorama

A graphical display-settings app for **Hyprland**, built with **Quickshell** (QML).
It exposes *everything* Hyprland can do with outputs, and handles monitor
brightness too, so you never have to hand-edit config files:

- Multi-monitor layout: drag-and-drop arrangement with edge snapping
- Resolution, refresh rate, and custom modes
- Fractional scaling, with only valid scales offered for each mode
- Rotation and flipping (all 8 transforms)
- Mirroring, enabling/disabling outputs
- **HDR and color management**: CM presets (`srgb`, `wide`, `hdr`, `hdredid`, …),
  10-bit, SDR brightness/saturation in HDR, luminance overrides, ICC profiles
- **VRR / adaptive sync**: off, always, or fullscreen-only, per monitor or globally
- **Brightness**: laptop backlight (`brightnessctl`), plus brightness, contrast and
  input source on external monitors over DDC/CI (`ddcutil`)
- Global render options: tearing, direct scanout, auto-HDR, hardware cursors
- Advertised capabilities from the EDID (HDR metadata, peak luminance, VRR range)
- Profiles that switch automatically when you plug a monitor in or out
- Safe apply: every change is live-previewed, and reverts after 15 seconds
  unless you confirm it

> Status: **Phase 7, polish and packaging.** Arrange,
> resize, rescale, rotate, mirror and turn displays on/off. Set color presets,
> 10-bit, HDR (including forcing it on panels Hyprland misreads), SDR-in-HDR
> brightness, luminance, ICC and VRR per monitor, plus Hyprland's global
> display options. Everything goes behind a 15 s "Keep these settings?"
> countdown and is saved into a marked section of `monitors.lua` (backed up
> every time, undoable). Brightness (laptop backlight, DDC/CI) applies
> instantly and stays in sync with the brightness keys. Profiles remember a
> layout per set of monitors and switch by themselves when you plug in or
> unplug (a few lines of Lua in the saved section, no daemon). Fully usable
> from the keyboard, reachable from the Omarchy menu, and packaged as an AUR
> `PKGBUILD`. See [PLAN.md](PLAN.md) for the roadmap.

## Requirements

| Component  | Version tested | Notes |
|------------|----------------|-------|
| Hyprland   | 0.56.2         | **Lua config only** (`hyprland.lua`), which must require the saved file — see *On a plain Hyprland install*. Legacy `hyprland.conf` is not supported (Hyprland removes it in 0.57). |
| Quickshell | 0.3.1          | Uses `Quickshell.Io` and `Quickshell.Hyprland` |
| Qt         | 6.11           | |
| `brightnessctl` | optional  | Laptop/backlight brightness |
| `ddcutil`  | optional       | External monitor brightness, contrast and input over DDC/CI. Needs the `i2c-dev` module and access to `/dev/i2c-*` |
| `edid-decode` | optional    | Enables the capability panel |
| Omarchy    | optional       | On Omarchy, turning a laptop panel off also sets Omarchy's `internal-monitor-disable` toggle, because its clamshell watcher re-enables an unflagged panel every couple of seconds; a profile that turns the panel off holds the same toggle while it is in force. Elsewhere this is a no-op. |

### On a plain Hyprland install

Panorama works on any Hyprland that uses the Lua config, Omarchy or not. The one
thing to set up is loading what it saves: it writes `~/.config/hypr/monitors.lua`,
and Hyprland reads that file only if your config requires it. Omarchy's
`hyprland.lua` already does; a stock one doesn't, so add this line at the **end**
of `hyprland.lua` — after any monitor rules of your own, since the last rule for
a monitor is the one that wins:

```lua
require("monitors")
```

Hyprland puts its own config directory on Lua's `package.path`, so nothing else
is needed (Omarchy's own `require("hypr.monitors")` works because its bootstrap
adds `~/.config` as well).

Panorama checks this at launch. If nothing loads the file it says so in the
status bar, holds the Save button, and the Save dialog offers to append the line
for you — `hyprland.lua` is backed up next to the other backups first. A
`hyprland.conf`-only setup is reported the same way; there is no fix for it
short of moving to the Lua config.

Off Omarchy the rest degrades on its own: the theme falls back to a neutral
palette, laptop brightness to `brightnessctl`, the on-screen display to
`notify-send`, and the laptop-panel toggle helper does nothing (there is no
clamshell watcher to appease).

Primary test system: **Omarchy** on a laptop with a Samsung ATNA60HS01 OLED
(2560×1600, 165 Hz, 10-bit, HDR10 with ~1100 nit peak, adaptive sync from 48 to 165 Hz,
backlight exposed as `nvidia_0`). Multi-monitor layouts can be tested without extra
hardware by using Hyprland headless outputs (`hyprctl output create headless`).

## Running

```bash
bin/panorama                       # launch, or focus the running window
bin/panorama --identify            # show each display's number on its screen
bin/panorama --quit
bin/panorama --revert              # put monitors.lua back as it was before the last save
bin/panorama --backups             # list backups (~/.local/state/panorama/backups)
./install.sh                       # link `panorama` into ~/.local/bin + a menu entry for this checkout
./install.sh --uninstall
(cd packaging/aur && PANORAMA_REPO=file://$PWD/../.. makepkg -si)   # system package from committed HEAD
node --test tests/                 # unit tests for lib/
tests/e2e/apply.sh                 # apply/keep/revert flow against a headless output
tests/e2e/persist.sh               # backup/write/restore helper on temp files
tests/e2e/internal-flag.sh         # Omarchy laptop-panel toggle helper on temp files
tests/e2e/save.sh                  # save + undo against a scratch copy of monitors.lua
tests/e2e/color.sh [MONITOR]       # 10-bit, HDR, VRR on a real monitor (reverted; flickers)
tests/e2e/brightness.sh [MONITOR]  # brightness backend, app ↔ keys sync, HDR-aware keys (restored)
tests/e2e/profiles.sh              # live profile switching on a headless output (file untouched)
tests/e2e/nudge.sh                 # keyboard move (Alt+arrows) on a headless output (draft only)
bin/panorama --brightness +5%      # what a brightness key binding runs (see Brightness below)
```

`install.sh` writes the desktop entry rather than copying it, with `Exec` set to
this checkout's `bin/panorama`. Menu entries are launched with the session's
PATH, not your shell's, so a bare `panorama` would only work with `~/.local/bin`
on both; an absolute path works wherever you cloned to. Re-run it after moving
the checkout. The AUR package keeps `Exec=panorama`, since it installs
`/usr/bin/panorama`.

A launch that fails has nowhere to print when it comes from a menu entry or a
keybinding, so with no terminal attached `bin/panorama` reports through
`notify-send` as well: Quickshell missing, Hyprland not running, a QML error
that keeps the window from appearing, and what `--revert` restored.

Scripting over IPC (same path as the UI, confirmation included):

```bash
qs -p /path/to/panorama ipc call panorama setScale eDP-1 1.25
qs -p /path/to/panorama ipc call panorama apply
qs -p /path/to/panorama ipc call panorama keep       # or: revert
qs -p /path/to/panorama ipc call panorama state      # JSON: phase, changes, errors, issues
```

Saving from scripts: `ipc call panorama preview` prints the section,
`save` writes it, `undoSave` restores the previous file.

Keys (press **?** or F1 in the app for this list):

| Key | Does |
|---|---|
| ← → ↑ ↓ | select the previous / next display |
| Alt + arrows | move the selected display 100 px (Shift + Alt: 10 px); it stays flush with its neighbours |
| Tab / Shift + Tab | move between controls (focused control has an accent outline) |
| Space / Enter | press a button, open a list, flip a switch; ← → on a slider |
| Ctrl + 1 … 4 | Settings, Color, Details, Global tab |
| Ctrl + Enter | apply |
| Enter / Esc | keep / revert while a change waits for confirmation |
| Ctrl + S / Ctrl + P | Save… / Profiles… |
| I | identify displays |
| Ctrl + R | refresh |
| Esc | close a dialog, or Panorama |

Suggested Hyprland binding, in `hyprland.lua`:

```lua
hl.bind("SUPER + CTRL + M", hl.dsp.exec_cmd("panorama"))
```

On Omarchy, in `~/.config/hypr/bindings.lua`, so it shows up in the keybindings
menu:

```lua
o.bind("SUPER + CTRL + M", "Display settings", { launch = "panorama" })
```

## How it works

```
             read                                   apply (live)
hyprctl -j monitors all  ──►  ┌──────────────┐  ──►  hyprctl eval 'hl.monitor({...})'
Hyprland.rawEvent (hotplug)──►│  Draft model │  ──►  brightnessctl / ddcutil setvcp
/sys/class/drm/*/edid    ──►  │  (QML + JS)  │
brightnessctl / ddcutil  ──►  └──────────────┘  ──►  managed block in monitors.lua (persist)
                                                       + hyprctl reload / configerrors
```

1. **Read.** Live state comes from `hyprctl -j monitors all`, which includes modes,
   `colorManagementPreset`, SDR values, `vrr`, `mirrorOf`, `disabled`, and
   `currentFormat`. It is refreshed on the `monitoradded`, `monitorremoved`, and
   `configreloaded` events. Brightness is read from `brightnessctl` and `ddcutil`,
   and each `ddcutil` display is matched to its Hyprland connector by DRM connector
   or EDID.
2. **Edit.** Changes go into a *draft*. The UI shows the draft next to the live
   state and highlights what changed. Brightness sliders are the exception: they
   apply immediately, since they are harmless and expected to be instant.
3. **Apply.** Each changed output gets a *complete* `hl.monitor({...})` rule
   through `hyprctl eval`. Hyprland merges rules by output name, so partial rules
   would keep stale fields like `disabled` or `mirror`. VRR changes go through
   a soft-property nudge to work around a Hyprland bug (see
   [PLAN.md](PLAN.md#phase-0-spikes--done-2026-09-10)). A "Keep these settings?"
   countdown appears on **every** screen. If you don't confirm, the previous
   snapshot is re-applied, with `hyprctl reload` as the fallback: a reload drops
   every unsaved live change.
4. **Save.** Confirmed settings are written to a managed block in
   `~/.config/hypr/monitors.lua` (a timestamped backup is taken first), then
   checked with `hyprctl configerrors`.

### The managed block

Panorama owns exactly one section of `~/.config/hypr/monitors.lua`
(`PANORAMA_MONITORS_FILE` points it elsewhere), appended at the end the
first time you save:

```lua
-- >>> panorama: managed section, edits inside are overwritten on save >>>
-- Rules for monitors that aren't connected stay here until you remove them.
hl.monitor({ output = "eDP-1", disabled = false, mode = "2560x1600@165", position = "0x0", scale = 1.6, transform = 0, mirror = "" })
hl.monitor({ output = "desc:Dell Inc. DELL U2723QE ABC123", disabled = false, mode = "3840x2160@60", position = "1600x0", scale = 1.5, transform = 0, mirror = "" })
-- <<< panorama <<<
```

- One complete rule per line, so Omarchy's `omarchy-hyprland-monitor-clamshell`
  (which parses this file as text) keeps working.
- Each monitor is saved by port (`DP-2`) or as "this monitor" (`desc:…`,
  which follows it to any port). Laptop panels default to the port.
- Rules for monitors that aren't plugged in right now are kept.
- Everything outside the markers (your own rules, Omarchy's `GDK_SCALE` env,
  comments) is left byte-for-byte untouched. The save preview lists rules
  outside the section that match a connected monitor: ones before it are
  overridden, ones after it win.
- Every save backs up the previous file first. If Hyprland's reload reports new
  config errors, the backup goes back automatically. "Undo save" and
  `panorama --revert` restore it on request.
- `omarchy refresh hyprland` resets `monitors.lua`, including this section
  (Omarchy keeps its own backup).

### Hyprland monitor fields we manage (`HL.MonitorSpec`)

Taken from `/usr/share/hypr/stubs/hl.meta.lua` in Hyprland 0.56:

| Field | UI |
|-------|----|
| `output` | Connector name (`DP-2`) or `desc:Make Model Serial`, which survives port changes |
| `mode` | Resolution@refresh picker, plus `preferred`, `highres`, `highrr`, and custom |
| `position` | Layout canvas; `auto` and the `auto-left`/`auto-right` style values available |
| `scale` | Slider limited to valid scales, plus `auto` |
| `transform` | 0–7 (rotate 90/180/270, flipped variants) |
| `mirror` | Mirror-of dropdown |
| `disabled` | Enable toggle |
| `bitdepth` | 8 / 10 |
| `vrr` | Use global (−1) / Off / On / Fullscreen only / Fullscreen with game or video content |
| `cm` | `auto`, `srgb`, `dcip3`, `dp3`, `adobe`, `wide`, `edid`, `hdr`, `hdredid`, showing requested vs effective preset |
| `sdr_eotf` | `default`, `auto`, `srgb`, `gamma22`, `gamma22force`, validated by Panorama (Hyprland silently ignores typos) |
| `sdrbrightness`, `sdrsaturation` | Shown when an HDR preset is active |
| `sdr_min_luminance`, `sdr_max_luminance` | HDR advanced |
| `min_luminance`, `max_luminance`, `max_avg_luminance` | HDR overrides, prefilled from EDID |
| `supports_hdr`, `supports_wide_color` | "Force HDR support", offered when the EDID advertises HDR but Hyprland doesn't detect it |
| `icc` | File picker |
| `reserved_area` | Advanced |

Global options: `misc.vrr`, `render.cm_enabled`, `render.cm_auto_hdr`,
`render.cm_sdr_eotf`, `render.direct_scanout`, `render.non_shader_cm`,
`render.icc_vcgt_enabled`, `general.allow_tearing`, `cursor.no_hardware_cursors`,
`cursor.no_break_fs_vrr`, `quirks.prefer_hdr`.

### Brightness

| Monitor | Backend (`bin/panorama-brightness`) | Controls |
|--------------|---------|----------|
| Laptop panel | `omarchy-brightness-display` on Omarchy, else `brightnessctl` | Brightness |
| External (DDC/CI) | `ddcutil` on the monitor's I2C bus | Brightness (VCP `0x10`), contrast (`0x12`), input source (`0x60`), color preset (`0x14`), whichever the monitor offers |
| Any monitor in HDR | Hyprland `sdrbrightness` (0.5–2×) | SDR brightness: the brightness control while in HDR (see below) |

**Brightness in HDR.** In SDR the backlight sets how bright the panel is. In
HDR the signal carries absolute brightness (PQ), and the panel ignores its
backlight. What you want to adjust then is how bright *ordinary* content
(the desktop, most apps) is placed: Windows calls it "SDR content
brightness", and Hyprland `sdrbrightness`, on top of the SDR white level
(`sdr_max_luminance`; Hyprland's default of 80 nits is dim, so Panorama uses
203 nits, the BT.2408 reference, when you switch to HDR). While a monitor is
in HDR, Panorama's brightness slider becomes SDR brightness, and so do the
HDR-aware brightness keys.

Brightness applies instantly: no countdown and no Apply. The value lives in
the hardware, and Panorama re-reads it every 1.5 s, so its sliders follow the
brightness keys. DDC is slow, so the monitor's bus is cached and writes run
one at a time, newest value first.

**Brightness keys.** On Omarchy the stock keys keep working and stay in sync
with Panorama. To make them HDR-aware (step SDR brightness while a monitor is
in HDR, the backlight otherwise), bind them to Panorama instead, in
`~/.config/hypr/bindings.lua`:

```lua
hl.unbind("XF86MonBrightnessUp")
hl.unbind("XF86MonBrightnessDown")
o.bind("XF86MonBrightnessUp", "Brightness up", "panorama --brightness --hdr +5%", { locked = true, repeating = true })
o.bind("XF86MonBrightnessDown", "Brightness down", "panorama --brightness --hdr 5%-", { locked = true, repeating = true })
```

Elsewhere `o.bind` doesn't exist; bind them with Hyprland's own function, which
gets a `notify-send` progress bubble instead of Omarchy's OSD:

```lua
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("panorama --brightness --hdr +5%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("panorama --brightness --hdr 5%-"), { locked = true, repeating = true })
```

(`panorama` on your `PATH` via `./install.sh`. In HDR the keys go through
Panorama when it's running; otherwise they change `sdrbrightness` in the
monitor's saved rule.)

### Troubleshooting: brightness has no effect

If the backlight value changes (`cat /sys/class/backlight/*/actual_brightness`)
but the screen doesn't, check whether the panel is in HDR: in HDR the panel
ignores its backlight, and the brightness control is SDR brightness (above).
An HDR panel can also stay in HDR mode after the compositor has switched back
to sRGB. On the test machine (Samsung OLED on NVIDIA) that happened after
repeated HDR on/off tests, and turning HDR on and off once more brought the
backlight back.

### Seeing a difference with HDR on

With HDR on, the desktop itself doesn't look very different, by design: it's
SDR content, placed at the SDR white level. The difference shows in HDR
content: HDR video (e.g. mpv with `--vo=gpu-next`), HDR games (gamescope /
Proton), HDR photos. For everyday use, the usual setup is to keep the
desktop in SDR (sRGB, 10-bit) with HDR support set to On. Hyprland's *Auto
HDR in fullscreen* (Global tab, on by default) then switches the panel to HDR
by itself while a fullscreen app shows HDR content, and back afterwards. On
panels Hyprland misreads, like the test OLED, the forced HDR support is what
makes auto HDR possible.

## Omarchy integration

The app runs as a **standalone** Quickshell config, so it works on any Hyprland
setup that uses the Lua config (see *On a plain Hyprland install*). On Omarchy
it also:

- picks up the current theme from `~/.local/state/omarchy/current/theme/colors.toml`
  (with a neutral fallback everywhere else);
- stays compatible with Omarchy's monitor scripts (see *The managed block*);
- sits alongside Omarchy's bar **Display** panel (quick brightness and scale)
  without replacing it. Panorama is the "full settings" view.

**Omarchy menu.** Add an entry under Setup (next to Monitors, which still
opens `monitors.lua` in the editor) in `~/.config/omarchy/extensions/omarchy-menu.jsonc`;
the menu reloads on save:

```jsonc
"setup.panorama": {"icon":"󰍹","label":"Display Settings","description":"Panorama: monitors, HDR, VRR, brightness, profiles","aliases":["panorama"],"action":"panorama"}
```

`omarchy menu summon panorama` then opens it directly.

**Scale hotkeys (SUPER + / and SUPER + ALT + /).** Omarchy's
`omarchy-hyprland-monitor-scaling` changes the scale live and records it in
`monitors.lua` *outside* Panorama's section, which loads later and wins. So a
hotkey change works until the next reload or login, then the saved scale comes
back. Panorama notices the difference (status **Not saved**, and the new
scale shows as the current one); press **Save…** to keep it. The hotkey also
resets the position to `auto`, which Save pins back to real coordinates.

## Project layout

```
Panorama.qml              the app: window, keys, IPC, per-screen overlays
shell.qml                 entry point: its own Quickshell instance (bin/panorama)
Panel.qml                 entry point: Omarchy shell plugin panel

services/                 singletons
  Hypr.qml                live monitor state (hyprctl JSON + events + poll)
  Draft.qml               pending edits over the live state
  Apply.qml               apply → confirm → keep/revert, SDR brightness queue
  Persist.qml             managed section: parse, save, undo, profiles
  Brightness.qml          backlight / DDC values via bin/panorama-brightness
  Edid.qml, Globals.qml   EDID summaries, global options
  Theme.qml, Command.qml  Omarchy-aware look; process runner

lib/                      pure JS (unit tested with node)
  monitor.js layout.js scale.js     layout math, snapping, clean scales
  draft.js                          live ↔ draft ↔ rule, validation
  lua.js block.js match.js          Lua serialization, managed section, desc: matching
  profiles.js                       profile handler Lua + helpers
  edid.js globals.js brightness.js

ui/
  LayoutCanvas.qml MonitorTile.qml  drag-to-arrange canvas
  Inspector.qml                     Settings / Color / Details / Global tabs
  SettingsPanel.qml ColorPanel.qml GlobalPanel.qml InfoSection.qml
  ActionBar.qml BrightnessStrip.qml
  SaveDialog.qml ProfilesDialog.qml KeysHelp.qml
  ConfirmOverlay.qml IdentifyOverlay.qml   per-screen layer-shell overlays
  PButton Toggle Dropdown Segmented Slider NumberField TextField SettingRow SectionHeader

bin/panorama              launcher (float rule, single instance, IPC, --revert, --brightness)
bin/panorama-persist      backup + atomic write + restore of monitors.lua
bin/panorama-brightness   backlight / DDC / HDR SDR brightness; key handler
share/applications/       desktop entry
install.sh                per-user install into ~/.local
tests/                    node unit tests, fixtures, e2e scripts
spikes/                   Phase 0 experiments (see PLAN.md)
docs/upstream/            draft bug reports for Hyprland
```

## Safety principles

- **No lockout.** Live changes always go through a countdown with automatic
  revert. `panorama --revert` and a keybinding hint are always available.
- **Never lose user config.** Only the managed block is rewritten, and a backup
  is taken every time.
- **No Lua injection.** Every string that ends up in Lua (connector names, EDID
  descriptions, file paths) goes through one strict escaper, and numbers are
  validated before serialization.
- **Verify.** After applying, the reported state is compared with the requested
  state, and `hyprctl configerrors` is checked after saving.

## License

MIT, see [LICENSE](LICENSE). © 2026 Arash, [arashlab.com](https://arashlab.com).
