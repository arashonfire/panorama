# Panorama: Plan

Each phase ends with something runnable and is tested on Omarchy (Hyprland 0.56.2,
Quickshell 0.3.1, internal HDR OLED plus headless outputs for multi-monitor).

## Decisions

| Topic | Decision |
|-------|----------|
| Name | **Panorama**, command `panorama` (free in the Arch repos and AUR as of 2026-09-10) |
| Persistence | Managed block with markers inside `~/.config/hypr/monitors.lua`, one-line rules, backup every time |
| Config format | Hyprland Lua config only (≥ 0.56). No `hyprland.conf` backend |
| Brightness | In scope: backlight (`brightnessctl`), DDC/CI (`ddcutil`), HDR `sdrbrightness` |
| Distribution | Standalone Quickshell config (`qs -p`), not an Omarchy shell plugin |

## Phase 0: Spikes ✅ (done 2026-09-10)

Scripts in `spikes/`: `headless.sh`, `merge.sh`, `edp.sh`, `vrr.sh`, `qs-probe/`.
Source references are Hyprland v0.56.2.

### Applying rules at runtime

- [x] **`hyprctl eval 'hl.monitor({...})'` applies immediately** (~3 ms per call).
      Mode, position, scale, transform, bitdepth, cm, sdr\*, mirror and disabled
      were all verified live. Errors come back as exit code 7 with a precise
      message (`field 'vrr': value 5 is more than the maximum of 3`,
      `unknown field 'x'`, `error applying field 'mode'`), and a failed call
      changes nothing.
- [x] **Rules merge by exact `output` string.** `hl.monitor` for an output that
      already has a rule updates that rule in place (`MonitorRuleManager::add`
      replaces same-name rules, and the parser starts from the existing one). A
      later partial rule therefore keeps `disabled = true` or `mirror = ...` from
      an earlier one. → **Panorama always sends a complete rule** with explicit
      `disabled = false`, `mirror = ""`, `transform = 0`, and so on.
- [x] **Precedence: the most recently added matching rule wins** (reverse
      iteration in `MonitorRuleManager::get`). Name and `desc:` rules are not
      ranked, so whichever comes later wins. `wlr-output-management` clients
      (wlr-randr, kanshi) override every rule. → Emit exactly **one rule per
      monitor**, and warn about other rules that match the same monitor.
- [x] **`hyprctl reload` drops every eval-applied rule** and restores the files.
      → Unsaved live changes are fragile: anything that reloads (Omarchy's
      clamshell and hot-plug handling, the user saving a config file) wipes them.
      Revert-before-save = re-apply the snapshot, with `hyprctl reload` as the
      emergency fallback.
- [x] **`hl.config({...})` works at runtime**, in both nested
      (`{ misc = { vrr = 1 } }`) and dotted (`{ ["misc.vrr"] = 1 }`) form.
      Read back with `hyprctl getoption` or `hl.get_config`. Unknown keys fail
      with exit code 7. Reload restores the file value.

### Field values (from `LuaBindingsConfigRules.cpp`, `Parser.cpp`, `TransferFunction.cpp`)

| Field | Accepted | Notes |
|-------|----------|-------|
| `mode` | `WxH@R`, `preferred`, `highres`, `highrr`, modelines | invalid → error |
| `position` | `XxY`, `auto`, `auto-left/right/up/down`, `auto-center-left/right/up/down` | |
| `scale` | number ≥ 0.25, `auto` | Hyprland snaps to a valid value (1.33 → 1.3333334) |
| `transform` | 0–7 | |
| `bitdepth` | only `10` means 10-bit; anything else is 8 | 16 silently → 8 |
| `cm` | `auto srgb dcip3 dp3 adobe wide edid hdr hdredid` | readback shows the **effective** preset: HDR falls back to `srgb` when unsupported |
| `sdr_eotf` | `default auto srgb gamma22 gamma22force` (or `0`–`3`) | **invalid values are silently treated as `default`**, so Panorama must validate them itself |
| `vrr` | −1 (use global `misc.vrr`), 0, 1, 2 (fullscreen), 3 (fullscreen game/video) | see the VRR bug below |
| `mirror` | output name; `""` or `"none"` clears it | `hyprctl` reports `mirrorOf` as a monitor **id**, not a name |
| `supports_hdr`, `supports_wide_color` | −1, 0, 1 | |
| defaults | sdr_min 0.2, sdr_max 80, sdrbrightness/saturation 1.0, min/max/max_avg luminance −1 (from EDID) | |

### Real panel (eDP-1, Samsung ATNA60HS01 OLED on NVIDIA)

- [x] 10-bit works live (`XRGB8888` → `XBGR2101010`), as do `wide`, `edid` and `dcip3`.
- [x] **HDR needs `supports_hdr = 1` on this panel.** `cm = "hdr"` and `"hdredid"`
      fall back to `srgb` even though `edid-decode` shows HDR10 (ST2084, BT.2020,
      1100 nit peak). The HDR data is in a DisplayID block that Hyprland doesn't
      pick up. With `supports_hdr = 1, supports_wide_color = 1`, HDR, `hdredid`
      and the luminance overrides all work. `grim` screenshots look correct in HDR.
      → Phase 4: compare what the EDID advertises with Hyprland's effective `cm`,
      and offer a **"Force HDR support"** switch when they disagree.
- [x] **VRR: vrr-only changes are ignored (Hyprland bug).**
      `CMonitorRule::compare()` (`MonitorRule.cpp`) never looks at `m_vrr`, so a
      rule that differs only in `vrr` counts as a full match, the monitor's
      active rule isn't replaced, and `ensureVRR` keeps using the old value. This
      also affects save + reload. **Workaround, verified in both directions:**
      send the rule once with a harmless soft-property nudge
      (`sdrsaturation = <value> + 0.0001`), then again with the real values
      (`spikes/vrr.sh`). → Report upstream.
- [x] The `vrr` field in `hyprctl` is Hyprland's `m_vrrActive` flag, which can be
      wrong. `ensureVRR` sets it to `true` even when the driver rejected adaptive
      sync, logging only "Pending output … does not accept VRR". → Show VRR as
      "requested", and check the log for that line to show a warning.
- [x] The panel is `vrr_capable` (aquamarine log). Only one refresh range is
      exposed to the OS (EDID advertises 48–165 Hz).

### Headless outputs

- [x] `hyprctl output create headless NAME` works (the name is honoured), with a
      single `1920x1080@60` mode. Custom modes, scale, transform, cm presets and
      mirror all behave normally. VRR is always `false` and HDR needs
      `supports_hdr = 1`. Description/make/model/serial are empty, so `desc:`
      matching can't be tested there. Good enough for layout testing.

### Omarchy

- [x] `omarchy-hyprland-monitor-clamshell` reads `monitors.lua` with `sed`, only
      one-line `hl.monitor({… output = "NAME" …})` rules, and only `scale` and
      `position` for the internal panel. When the internal panel's active scale
      differs from the configured one, it evals `mode = "preferred", position,
      scale`. Because rules merge by name, that keeps our other fields **only if
      the internal panel's rule uses the connector name** (not `desc:`). Lid close
      writes `~/.local/state/omarchy/toggles/hypr/internal-monitor-clamshell.lua`,
      which loads after `hypr.monitors` and so correctly overrides our block.
- [x] `omarchy-hyprland-monitor-scaling` (the scale hotkeys) evals
      `{ output = <connector>, mode, position = "auto", scale }`. It merges into
      our rule too, but resets `position` to `auto`. It persists by editing
      `local omarchy_monitor_scale` / the catch-all, which our block overrides,
      so a hotkey change won't survive a reload while Panorama manages that
      monitor. → Phase 7: documented (README, *Omarchy integration*): Panorama
      shows "Not saved" after a hotkey change and Save keeps it.
- [x] `omarchy refresh hyprland` resets `monitors.lua`, including our block, after
      taking a backup. → `panorama --revert` should also be able to restore
      from Panorama's own backups.

### Brightness

- [x] `brightnessctl -d nvidia_0` works (0–100, currently 18). `ddcutil detect`
      reports `DRM_connector: card1-eDP-1` per display, which can be matched to
      the Hyprland name by stripping `cardN-`. It correctly marks the laptop
      panel "Invalid display … Laptop displays do not support DDC/CI". The
      `/dev/i2c-*` ACLs give this user access. External DDC is untested: no
      external monitor is connected.

### Quickshell (0.3.1)

- [x] `FloatingWindow` gets **tiled** by Hyprland/Omarchy. Its class is
      `org.quickshell`, and the title comes from `title:`. A runtime rule works:
      `hl.window_rule({ name = "panorama-float", match = { title = "^Panorama$" },
      float = true, center = true, size = { 1100, 720 } })` → floating,
      1100×720, centred. → `bin/panorama` installs this rule before launching.
- [x] `Variants { model: Quickshell.screens }` + `PanelWindow` on
      `WlrLayer.Overlay` produces one overlay per screen, and follows hot-plug
      (appeared on a new headless output).
- [x] `Hyprland.rawEvent` delivers `monitoradded(v2)`, `monitorremoved(v2)` and
      `configreloaded`.
- [x] `Hyprland.monitors` is **empty** in `Component.onCompleted`, so state
      comes from `hyprctl -j monitors all` through `Process`.
- [x] `FileView.setText` writes files. `Quickshell.screens` reports logical size
      with dpr 2 at scale 1.6 (fractional scaling is rounded for Qt).

### Tooling notes

- A watchdog started with `setsid … &` is not the same PID as `$!` (setsid
  forks). Use a pidfile, as in `spikes/vrr.sh`.

## Phase 1: Read-only viewer ✅ (done 2026-09-10)

- [x] `shell.qml` + `FloatingWindow`, with a `Theme` singleton that follows
      Omarchy's `colors.toml`, `shell.toml` (`[font] base-size`) and Hyprland's
      `decoration:rounding`, with neutral defaults elsewhere
- [x] `services/Hypr.qml`: `hyprctl -j monitors all`, refreshed on
      monitor/workspace/`configreloaded` events (debounced) plus a 2 s poll for
      eval-applied changes. The array is only replaced when the JSON changes.
- [x] Layout canvas: tiles at logical size (size / scale, axes swapped for
      transforms 1/3/5/7), fitted and centred, numbered left→right. Disabled and
      mirroring outputs go in a "Not in layout" tray.
- [x] Inspector: Display, Mode, Layout, Color, Sync & rendering, Physical, State,
      plus tags (Focused, HDR, 10-bit, VRR, …). Values are selectable.
- [x] "Identify": a numbered card on every screen for 3 s (layer-shell overlay,
      follows hot-plug)
- [x] Keyboard: ←/→ select, I identify, Ctrl+R refresh, Esc close
- [x] `bin/panorama`: float rule + `qs -n -d -p`. A second launch calls the IPC
      `show` and focuses the window with `hl.dsp.focus({ window = "title:^Panorama$" })`.
      Also `--identify` and `--quit`. `install.sh` symlinks the launcher and
      `.desktop` file into `~/.local`.
- [x] `lib/monitor.js`: pure helpers (layout math, formatting, inspector data),
      12 node tests (`node --test tests/`) against a real `hyprctl` fixture

Verified on the OLED plus headless outputs: one monitor, two side by side at
different y, rotated portrait, disabled (tray), identify, and relaunch → focus.
Loads with no QML warnings.

Findings:
- `hyprctl output remove` fails ("output not found") while a headless output
  is **disabled or mirroring**. Re-enable it first. A reload re-enables it.
- Hot-plug and mirroring moves workspaces: eDP-1 was left showing a fresh,
  empty workspace. → Phase 2 and later: remember the active workspace per
  monitor before applying, and restore it afterwards.
- Omarchy's default window opacity makes the app slightly see-through. That's
  the user's theme, so it's left alone.

## Phase 2: Core editing + safe apply ✅ (done 2026-09-10)

- [x] `lib/lua.js`: value → Lua serializer. Strings are always quoted and
      escaped (control characters as `\ddd`), numbers must be finite, and keys
      must be identifiers. Round-trip tested against a real Lua interpreter.
- [x] `lib/scale.js`: Hyprland's rule (k/120 with whole-pixel logical size),
      its nearest-value search, presets, and −/+ stepping
- [x] `lib/layout.js`: edge snapping while dragging; on drop, settle flush
      against the nearest monitor sharing at least ¼ of the shorter edge, with
      no overlap. Auto-place on enable/unmirror, and neighbours shift on resize.
- [x] `lib/draft.js`: live → config, merge, human-readable diff, normalisation
      to 0,0, complete-rule builder, validation (no display left, mirror
      chains, unclean scale, overlap), verification, workspace restore
- [x] `services/Draft.qml`: edits layered over live state (fields back at their
      live value stop counting). Reset.
- [x] `services/Apply.qml`: snapshot → one `hyprctl eval` → 15 s "Keep these
      settings?" → keep, or revert by re-applying the snapshot (`hyprctl
      reload` as fallback). Workspaces are restored after both. A reload during
      the countdown is detected. Quitting mid-countdown reverts first.
- [x] Editors (Settings tab): enabled, resolution, refresh, scale (stepper +
      clean presets), rotation, flip, mirror. Changed rows get an accent bar.
      Draggable canvas tiles, a view that freezes while dragging, an "edited"
      marker, an action bar with the diff and errors, and a per-screen
      confirmation card.
- [x] IPC for scripting and tests: `select`, `setEnabled`, `setMode`,
      `setScale`, `setTransform`, `setMirror`, `move`, `reset`, `apply`,
      `keep`, `revert`, `state`
- [x] Tests: 37 unit tests; `tests/e2e/apply.sh` (23 checks, headless output
      only) covers apply/revert, apply/keep, timeout, off/on with workspace
      restore, validation blocking, and a reload during the countdown

Finding: **monitors at an automatic position get re-placed by Hyprland**
whenever another monitor gets an explicit rule. Omarchy's catch-all is
`position = "auto"`, so applying a headless output at 1600x0 pushed eDP-1 from
0,0 to 2880,0. → Every apply pins *all* placed monitors (`applySet`). Rules
identical to the active one are skipped by Hyprland, so the cost is one
modeset per monitor the first time. Revert and verification cover the same set.

Not yet exercised by hand: mouse dragging on the canvas and the dropdown popups
(the e2e test drives the same Draft functions over IPC).

Moved to Phase 4, since colour and VRR aren't editable yet:
- VRR apply path: soft-property nudge, then the real values
- Verification comparing requested vs effective `cm`

## Phase 3: Persistence ✅ (done 2026-09-10)

- [x] `lib/block.js`: parse `monitors.lua` (section markers, every uncommented
      `hl.monitor` rule, and where it sits relative to the section), render the
      section in place or append it, `isSaved`, and conflicts (rules after the
      section win, rules before it lose). Two sections, missing or stray markers
      → refuse to save and say which line.
- [x] One complete rule per connected monitor. Saved rules for monitors that
      aren't connected are kept verbatim, so saving at home doesn't drop the
      office monitor.
- [x] Port vs monitor matching ("Save as" in Settings). `desc:` is a
      prefix match in Hyprland, so it's only offered when no other connected
      monitor's description starts with the same text. Laptop panels default
      to the port (Omarchy's clamshell script looks them up by connector); a
      rule already in the section keeps its style.
- [x] `bin/panorama-persist`: backup to `~/.local/state/panorama/backups`
      (30 kept; a missing file is recorded as `.absent`), `luac -p` check,
      atomic replace in the same directory, writes through symlinks, keeps
      permissions. `restore` takes a `.before-restore` safety copy and is
      repeatable.
- [x] `services/Persist.qml`: save = config errors before → write → `hyprctl
      reload` → config errors after. New errors put the backup straight back
      and reload again. The live layout is verified against the pre-save
      snapshot. Undo save. The file is watched, so outside edits show up.
- [x] UI: status badge (Saved / Live · not saved / Not saved by Panorama yet /
      needs attention), `Save…` (Ctrl+S) opens a preview of the exact section
      plus conflicts, and "Undo save" in the action bar
- [x] `panorama --revert` (restore the newest backup and reload) and
      `panorama --backups`
- [x] `services/Command.qml`: shared process runner (stdout+stderr, stdin,
      exit code); Apply uses it too
- [x] Tests: 46 unit tests, including Omarchy's stock `monitors.lua` and a JS
      replica of the clamshell script's `sed` parsing;
      `tests/e2e/persist.sh` (18 checks, temp files); `tests/e2e/save.sh`
      (16 checks: a separate instance saving to a scratch copy, then undo)

Not exercised yet: the automatic rollback when a save introduces new config
errors. A correct section can't produce one, and the scratch-file test doesn't
make Hyprland read the scratch file.

## Phase 4: HDR, color & VRR ✅ (done 2026-09-10)

- [x] **Requested vs effective.** Color/VRR fields in the draft come from what
      the monitor last *asked for*: a rule applied this session
      (`Apply.appliedRules`), else its saved rule, read back with
      `lua.parseCall`. Only without either are they inferred from `hyprctl`.
      Layout always comes from live. This keeps an HDR request that fell back
      to sRGB, or a VRR flag that lies, from overwriting the request.
- [x] Runtime rules are complete (every color/sync field explicit, because
      Hyprland merges same-name rules). Saved rules are compact (Hyprland
      defaults left out; the file is read from scratch).
- [x] `lib/edid.js` + `services/Edid.qml`: `edid-decode` on every connector.
      Reads HDR10/HLG (CTA static metadata, even inside DisplayID), content
      luminance (falls back to DisplayID native values), BT.2020/DCI-P3,
      bit depth, and VRR range (Adaptive Sync blocks, vendor block, range
      limits). sysfs reports these files as size 0, so no `-s` check.
- [x] Color tab: preset (picking HDR turns on 10-bit), 10-bit, HDR support /
      wide color (Auto/On/Off), and for HDR: SDR brightness/saturation sliders,
      white/black level, SDR transfer, and a panel-luminance override
      pre-filled from EDID. Also an ICC profile path and VRR mode (with "use
      global", the EDID range and Hyprland's reported state). Shows when
      Hyprland is doing something else, with a one-click "Force HDR".
- [x] Global tab (`lib/globals.js`, `services/Globals.qml`): 11 options from
      Hyprland's option registry, grouped Sync / Rendering / Color, with help
      text. They go through the same apply → confirm → revert flow (`hl.config`)
      and are saved as one `hl.config` line in the section (only options changed
      through Panorama).
- [x] VRR apply path: nudged rule first (`sdrsaturation + 0.0001`), the real
      rule 500 ms later, both for apply and revert. Afterwards the Hyprland log
      is checked for "Pending output … does not accept VRR".
- [x] Verification: HDR fallback (with the right hint), refused 10-bit, SDR
      brightness, and global options that didn't stick
- [x] Tests: 63 unit tests (`edid`, `globals`, `parseCall`, requested-vs-live);
      `tests/e2e/color.sh` on the OLED (14 checks: 10-bit, forced HDR + SDR
      brightness, VRR through the nudge, a kept HDR change in the save preview,
      reload clears it). Earlier suites re-run: `apply.sh` 23/23.

Findings:
- **Forcing HDR also needs wide color.** In Hyprland, `supportsHDR()` returns
  false unless `supportsWideColor()` is true. Auto wide color comes from
  libdisplay-info's `supportsBT2020`, which this panel's EDID also hides in the
  DisplayID-embedded CTA block. → "HDR support: On" also forces wide color, and
  verification says so when only HDR is forced.
- The HDR/cm fallback is re-evaluated in `applyMonitorRuleSoft`, so a
  soft-only change (no modeset) is enough to switch HDR on.
- An ICC profile replaces the `cm` preset entirely. Removing one can't be done
  at runtime (an empty `icc` is rejected), so it only takes effect after saving.
- `render:cm_enabled` needs a Hyprland restart to take full effect; the Global
  tab says so.

## Phase 5: Brightness (and the brightness keys) ✅ (done 2026-09-11)

On Omarchy the keyboard brightness keys (`XF86MonBrightnessUp/Down`, with
Shift for max/min and Alt for fine steps) run `omarchy-brightness-display`.
The brightness itself lives in the hardware (sysfs backlight, or the monitor
over DDC/CI), so the keys and Panorama agree as long as Panorama re-reads it
and picks the same backlight device.

- [x] `bin/panorama-brightness`: one backend for the app and the keys (`list`,
      `get`, `set`, `vcp`, `caps`, `key`)
      - **Laptop panels:** `omarchy-brightness-display --monitor X` (same
        device choice and step rounding as Omarchy's keys), else
        `brightnessctl` on the first backlight
      - **External monitors:** `ddcutil` on the monitor's I2C bus, matched by
        `DRM connector`. The bus is cached (detection takes ~0.9 s), and "no
        DDC/CI" is cached for 60 s.
      - Steps like Omarchy: `+5%`/`5%-` move by 1 at or below 5 %, never below 1 %
- [x] `services/Brightness.qml`: polls `list` every 1.5 s (20 ms for a laptop
      panel), so sliders follow the keys. Sets are applied at once, newest
      value wins, and a poll never pulls back a slider that was just moved.
- [x] Settings tab: brightness slider first. For DDC/CI monitors also contrast,
      input source and color preset, only if the monitor's capabilities list
      them. Says why when a monitor can't be adjusted, and points to SDR
      brightness while in HDR.
- [x] Brightness strip under the canvas when two or more monitors are adjustable
- [x] `panorama --brightness [--hdr] (+N% | N%- | N%)` for key bindings: the
      focused monitor, with `omarchy-osd` or a `notify-send` progress bubble.
      Overlapping key repeats are dropped (flock), like Omarchy.
- [x] HDR-aware keys (`--hdr`): on a monitor in HDR, the keys step Hyprland's
      `sdrbrightness` by 0.05 through the running app (a complete rule, no
      countdown, marked live-but-unsaved); otherwise the backlight
- [x] `lib/brightness.js` (parsers for `list`, `ddcutil getvcp --brief`,
      `capabilities`; key steps; SDR steps) with 5 unit tests (68 total)
- [x] `tests/e2e/brightness.sh` (14 checks): backend steps, the app following
      a change made through Omarchy's command, app → backlight, the key
      command, and HDR-aware keys stepping SDR brightness 1 → 1.05 → 1.1
      without touching the backlight

Follow-up (2026-09-11): **the backlight had no visible effect on the test
OLED, and the cause was HDR, not the driver.** The backlight value changed but
the panel didn't. I first blamed the NVIDIA driver and added software dimming
(hyprsunset gamma). That was wrong, and it's removed. The user found that
turning HDR on and off once made the backlight work again. After the many HDR
tests, the panel had stayed in HDR mode, where an HDR panel ignores its
backlight, even though Hyprland reported sRGB. Changes:
- [x] While a monitor is in HDR, the Settings brightness slider is **SDR
      brightness** (`sdrbrightness`, 0.5–2×), applied at once like the keys;
      hints explain the HDR brightness model
- [x] HDR-aware keys no longer need Panorama running: without it,
      `panorama-brightness` sends a partial rule that Hyprland merges into the
      monitor's same-name rule (only when Panorama's saved section has one;
      a new rule would start from defaults)
- [x] Switching to HDR in the Color tab also sets SDR white to 203 nits
      (BT.2408; Hyprland's default 80 is dim) and, when the EDID advertises
      HDR10, forces HDR + wide color support
- [x] README: brightness in HDR, why HDR looks similar on the desktop, and the
      "SDR desktop + forced HDR support + auto HDR in fullscreen" setup
- [x] Found along the way: applied-but-unsaved state lived only in memory, so
      after a Panorama restart the draft fell back to the saved rule (sRGB)
      while Hyprland still ran HDR, and the next HDR brightness key would
      have switched HDR off. `fromLive` now reconciles: Hyprland's effective
      values win where only a request can explain them (non-sRGB preset,
      10-bit, SDR values; HDR on screen ⇒ HDR/wide color support forced).
- Open: detecting a panel stuck in HDR mode (Hyprland reports sRGB) isn't
  possible from Hyprland's state; the troubleshooting note covers it

Not done / not tested:
- Rebinding the keys to `panorama --brightness --hdr` is the user's choice;
  Omarchy's default bindings already stay in sync with the app. The README
  has the snippet.
- DDC/CI (external brightness, contrast, input, preset) and the brightness strip
  are untested on hardware: no external monitor was connected. Parsers are
  unit-tested against ddcutil 2.2.7 output formats.
- Apple displays (Omarchy's `omarchy-brightness-display-apple`) aren't handled
  by Panorama's backend.
- Remembering brightness per profile moves to Phase 6.

## Phase 6: Profiles & hotplug ✅ (done 2026-09-11)

- [x] Profile = the layout for one exact set of connected monitors:
      `{ name, monitors: [{ match, port }], rules, workspaces }`. `match` is
      how the monitor is selected (port or `desc:`, same as the saved rules);
      `port` is where it was, for monitors that are connected but turned off.
- [x] Auto-switch without a daemon: the section gets a small Lua function
      plus one `panorama_profiles({ profiles }, { base rules })` call. At load,
      and on `monitor.added`/`monitor.removed`, it picks the profile whose
      monitors are exactly the connected ones and applies its rules and
      workspace rules; with no match it re-applies the base rules. It only
      re-applies when the matching profile (or the lid state) changed: turning
      a display off or on fires those events too, and re-applying the profile
      then would turn it straight back on.
- [x] Connected set = Hyprland's enabled monitors (with descriptions) plus
      connected-but-off connectors from `/sys/class/drm/*/status`, because
      Hyprland's Lua doesn't list disabled monitors. This also picks the right
      profile at startup, before any output is up.
- [x] Omarchy clamshell: while `internal-monitor-clamshell.lua` exists (lid
      closed with an external monitor), the handler leaves the laptop panel's
      rules alone.
- [x] Omarchy's watcher polls every 2 s while docked with the lid open and
      re-enables a disabled laptop panel (`sync_internal_scale` reads the scale
      of enabled monitors only, so an off panel never matches), which no monitor
      rule can survive. Turning one off therefore also sets Omarchy's own
      `internal-monitor-disable` toggle, via `bin/panorama-omarchy-internal`:
      set before the rules go out, put back when the change is reverted, and a
      no-op off Omarchy. `tests/e2e/internal-flag.sh` (17 checks, temp files).
- [x] Never a session with no screen: rules that would leave every connected
      display off are applied and then overridden, each connected output coming
      back at Hyprland's defaults. Omarchy's "laptop display off" toggle counts
      only while another display is actually showing something, and is cleared
      once the external goes (the toggle directory loads *after* `monitors.lua`,
      so leaving it would re-disable the panel on the next reload). `connected()`
      drops ports the kernel no longer reports even when Hyprland still lists
      them, so an unplug in progress is never read as a live display; outputs
      with no DRM connector at all (`hyprctl output create`) still count. On reload, Omarchy's toggle file loads after `monitors.lua`
      and wins anyway.
- [x] App: Profiles… dialog (add for the connected monitors, rename, delete,
      default workspaces per monitor, "matches now"), a "Profile: …" header
      badge for the running one, and a save-dialog note when saving updates
      it. Saving refreshes the profile that matches the connected monitors.
      The running profile's rules are the requested values for editing.
- [x] `lib/match.js` (shared matching), `lib/profiles.js`, `parseCall` with
      several arguments; a section whose profiles can't be read is refused,
      not overwritten
- [x] Tests: 77 unit tests, including the generated Lua run in a real Lua
      interpreter against a stubbed `hl` (match / no match / turned-off panel /
      startup / lid closed / hot-plug event), `luac -p` of a whole file with
      profiles, and "Omarchy's clamshell parser still sees exactly one eDP-1
      rule". `tests/e2e/profiles.sh` (7 checks) registers the real handler with
      `hyprctl eval` and hot-plugs a headless output: profile layout +
      workspace rule on plug, base layout on unplug, profile again on re-plug.

Spike findings:
- `hl.on` handlers get the monitor (userdata, `.name`); `hl.get_monitors()`
  already reflects the change. Subscriptions and Lua globals are gone after a
  config reload, so handlers in the file never pile up.
- Disabled monitors are invisible to Lua (`hl.get_monitors()`,
  `hl.get_monitor(name)`), and disabling or enabling one fires no event.
- `io.open`/`io.popen` work inside Hyprland's Lua. Re-adding a rule identical
  to the active one causes no modeset, so re-applying a profile on every event
  is free. Workspace rules accept `desc:` monitors; a reload clears them.
- `hyprctl eval` treats Lua that starts with `--` as its own flags (test-only
  pitfall; the file is read directly).

Not done / not tested:
- Brightness per profile (optional) is not done.
- Real hot-plug with a physical external monitor, and profiles that turn the
  panel off while docked, are only covered by the Lua stub tests (no external
  monitor here).
- Screenshots of the Profiles dialog: the screen was off (DPMS) during testing.

## Phase 7: Polish

- [x] Keyboard navigation: Tab order through every control with an accent
      focus outline (buttons, switches, lists, sliders, fields); Ctrl+1…4 tabs;
      Ctrl+P profiles; Alt+arrows move the selected display (100 px, Shift 10 px)
      through `Draft.nudge`, which settles it flush like a drop; ? / F1 shortcut
      sheet (`ui/KeysHelp.qml`). Dialogs disable the window behind them so Tab
      stays inside. Accessible roles and names on all controls.
- [x] Omarchy menu entry: additive `setup.panorama` ("Display Settings") in
      `~/.config/omarchy/extensions/omarchy-menu.jsonc`; the stock Monitors
      entry is untouched.
- [x] ~~Bar-widget launch hook~~: skipped. It would mean cloning Omarchy's
      Display plugin and maintaining the fork; the menu entry and a keybinding
      cover it.
- [x] Omarchy scale hotkeys: documented (README). Syncing hotkey changes back
      automatically would mean Panorama writing the file behind the user's back.
- [x] Upstream Hyprland reports drafted in `docs/upstream/` (not filed; filing
      is the maintainer's call):
      `hyprland-vrr-only-rule-ignored.md` (`CMonitorRule::compare()` ignores
      `m_vrr`), `hyprland-vrr-active-when-refused.md` (`ensureVRR` sets
      `m_vrrActive` when adaptive sync was rejected),
      `hdr-displayid-cta-not-detected.md` (HDR metadata / BT.2020 inside a
      DisplayID extension's CTA block not picked up, Samsung ATNA60HS01),
      `aquamarine-backup-crtc-modeset-einval.md` (a powered-down output is
      parked on a backup CRTC that is not checked against its `possible_crtcs`,
      so bringing it back fails with `EINVAL` until a udev hotplug re-probe
      reassigns a usable one. An idle DPMS off on a single-panel laptop is
      enough: the machine then cannot wake. Not Panorama's doing, but Panorama's
      turn-a-display-off is one of the ways in)
- [ ] Investigate (Hyprland / NVIDIA): after repeated HDR ↔ sRGB switches the
      OLED stayed in HDR mode (backlight ignored) while Hyprland reported
      sRGB; one more HDR on/off cleared it. Needs a reliable repro first.
- [x] Packaging: `packaging/aur/PKGBUILD` (`panorama-git`) installs the app
      to `/usr/share/panorama`, links `/usr/bin/panorama`, runs the unit tests
      in `check()`. Builds locally with `PANORAMA_REPO=file://…`. Repository
      published (`source` points at GitHub, `url` at arashlab.com), MIT
      `LICENSE` added, `packaging/aur/.SRCINFO` generated. A full local build
      of r8.d18d255 passes: `check()` ran the 84 unit tests and the package
      holds only `/usr/share/panorama`, the `/usr/bin/panorama` symlink, the
      desktop file, README and LICENSE.
- [ ] Submit to the AUR: push `PKGBUILD` + `.SRCINFO` to
      `ssh://aur@aur.archlinux.org/panorama-git.git`. Refresh both first
      (`pkgver`, then `makepkg --printsrcinfo > .SRCINFO`) — they carry the
      commit they were last generated from.
- [x] Portability off Omarchy: everything Omarchy-specific already degrades
      (theme, `omarchy-brightness-display`, OSD, the laptop-panel toggle), but
      a stock `hyprland.lua` requires nothing, so the saved file was written
      and then ignored — the only sign being the vague post-reload warning.
      `panorama-persist loaded` now reports `loaded` / `missing` / `legacy`
      (a `hyprland.conf` setup) / `unknown`; Panorama says so at launch, holds
      Save, and `panorama-persist require` appends `require("monitors")` to
      `hyprland.lua` (backed up first) from a button in the Save dialog.
      Backups are name-filtered so that copy is never restored over
      `monitors.lua`. Documented under *On a plain Hyprland install*, with
      `hl.bind` examples for the bindings that were only given as Omarchy's
      `o.bind`. `tests/e2e/persist.sh` covers all four states (28 checks).
- [x] Docs pass: README shortcut table, Omarchy menu and hotkey notes,
      current project layout.
- [ ] README screenshots (need the screen on; grim can't capture while DPMS
      is off)

Findings:
- Keyboard move can't jump a display to another side of its neighbour: a step
  that leaves a gap settles back flush. Sliding along the shared edge works;
  bigger moves are a drag.
- Quickshell hot reload doesn't refresh `IpcHandler` functions: a new or
  changed IPC function needs a restart (`panorama --quit`, then `panorama`).
- Verified with `wtype` against the real window: Ctrl+1/2, F1, Esc and Ctrl+P
  do what the sheet says; `tests/e2e/nudge.sh` covers Alt+arrows.
