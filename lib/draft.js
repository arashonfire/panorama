.pragma library
.import "monitor.js" as M
.import "scale.js" as S
.import "layout.js" as L
.import "lua.js" as Lua

// Editable monitor settings ("configs") and everything needed to turn them
// into Hyprland rules and check the result.
//
// Layout fields always come from the live state. Color and sync fields come
// from the requested rule when there is one (Panorama's saved section, or a
// rule applied this session), because Hyprland only reports what took effect:
// an HDR request that fell back reads as "srgb", and its VRR flag can be wrong.
// Without a requested rule they are inferred from the live state.

var LAYOUT = ["enabled", "width", "height", "refresh", "x", "y", "scale", "transform", "mirror"];

// Hyprland's defaults (LuaBindingsConfigRules.cpp).
var COLOR_DEFAULTS = {
  bitdepth: 8,
  cm: "srgb",
  sdr_eotf: "default",
  sdrbrightness: 1,
  sdrsaturation: 1,
  sdr_min_luminance: 0.2,
  sdr_max_luminance: 80,
  min_luminance: -1,
  max_luminance: -1,
  max_avg_luminance: -1,
  supports_hdr: 0,
  supports_wide_color: 0,
  icc: "",
  vrr: -1
};
var COLOR = Object.keys(COLOR_DEFAULTS);
var EDITABLE = LAYOUT.concat(COLOR);

var INT_FIELDS = ["sdr_max_luminance", "max_luminance", "max_avg_luminance"];
var FLOAT_FIELDS = ["scale", "sdrbrightness", "sdrsaturation", "sdr_min_luminance", "sdr_max_luminance",
                    "min_luminance", "max_luminance", "max_avg_luminance"];
var CM_PRESETS = ["auto", "srgb", "dcip3", "dp3", "adobe", "wide", "edid", "hdr", "hdredid"];
var SDR_EOTFS = ["default", "auto", "srgb", "gamma22", "gamma22force"];
var VRR_LABELS = { "-1": "Use global setting", "0": "Off", "1": "On", "2": "Fullscreen only", "3": "Fullscreen games & video" };
var TRISTATE = { "-1": "forced off", "0": "auto", "1": "forced on" };

function find(list, name) {
  for (var i = 0; i < list.length; i++) {
    if (list[i].name === name) return list[i];
  }
  return null;
}

function roundScale(scale) {
  return Math.round(scale * 120) / 120;
}

function numOr(v, fallback) {
  return typeof v === "number" && isFinite(v) ? v : fallback;
}

// The advertised refresh rate closest to `refresh` for this resolution, so a
// live 164.99899 becomes the mode's 165.
function closestRefresh(availableModes, width, height, refresh) {
  var best = null;
  (availableModes || []).forEach(function (text) {
    var m = M.parseMode(text);
    if (!m || m.width !== width || m.height !== height) return;
    if (best === null || Math.abs(m.refresh - refresh) < Math.abs(best - refresh)) best = m.refresh;
  });
  return best !== null ? best : Math.round(refresh * 100) / 100;
}

// Rule values the way Hyprland stores them: booleans become numbers.
function normalizeColor(key, v) {
  if (key === "vrr" || key === "supports_hdr" || key === "supports_wide_color") return v === true ? 1 : v === false ? 0 : Number(v);
  if (key === "bitdepth") return Number(v) === 10 ? 10 : 8;
  if (FLOAT_FIELDS.indexOf(key) >= 0) return Number(v);
  return String(v);
}

function inferColor(mon) {
  return {
    bitdepth: M.pixelFormat(mon.currentFormat).bits === 10 ? 10 : 8,
    cm: mon.colorManagementPreset || COLOR_DEFAULTS.cm,
    sdrbrightness: numOr(mon.sdrBrightness, 1),
    sdrsaturation: numOr(mon.sdrSaturation, 1),
    sdr_min_luminance: numOr(mon.sdrMinLuminance, 0.2),
    sdr_max_luminance: numOr(mon.sdrMaxLuminance, 80)
  };
}

function fromLive(mon, monitors, requested) {
  var width = mon.width, height = mon.height, refresh = mon.refreshRate;
  if (!(width > 0 && height > 0)) {
    var preferred = M.groupModes(mon.availableModes)[0];
    width = preferred ? preferred.width : 1920;
    height = preferred ? preferred.height : 1080;
    refresh = preferred ? preferred.refreshes[0] : 60;
  }
  var source = M.mirrorSource(mon, monitors || []);
  var cfg = {
    name: mon.name,
    enabled: !mon.disabled,
    width: width,
    height: height,
    refresh: closestRefresh(mon.availableModes, width, height, refresh),
    x: mon.x,
    y: mon.y,
    scale: mon.scale > 0 ? roundScale(mon.scale) : 1,
    transform: mon.transform || 0,
    mirror: source ? source.name : ""
  };
  var values = requested || inferColor(mon);
  COLOR.forEach(function (k) {
    cfg[k] = values[k] === undefined ? COLOR_DEFAULTS[k] : normalizeColor(k, values[k]);
  });
  if (requested) reconcile(cfg, inferColor(mon));
  return cfg;
}

// A requested rule can be older than what Hyprland runs: a change applied by
// an earlier Panorama session and never saved, for example. Hyprland's
// effective values win where they can only have come from a request: a color
// preset other than sRGB (fallbacks only ever go to sRGB), 10-bit output (8-bit
// is the fallback), and the SDR values, which never fall back. HDR on screen
// also means Hyprland treated the panel as HDR and wide-color capable, so
// those count as forced on. "auto", ICC and VRR can't be read back and stay
// as requested.
function reconcile(cfg, live) {
  if (cfg.cm !== "auto" && !cfg.icc && live.cm !== "srgb" && live.cm !== cfg.cm) {
    cfg.cm = live.cm;
    if (M.isHdr(live.cm)) {
      if (cfg.supports_hdr === 0) cfg.supports_hdr = 1;
      if (cfg.supports_wide_color === 0) cfg.supports_wide_color = 1;
    }
  }
  if (live.bitdepth === 10) cfg.bitdepth = 10;
  ["sdrbrightness", "sdrsaturation", "sdr_min_luminance", "sdr_max_luminance"].forEach(function (k) {
    if (!sameField(k, cfg[k], live[k])) cfg[k] = live[k];
  });
}

function sameField(field, a, b) {
  if (field === "refresh") return Math.abs(a - b) < 0.05;
  if (FLOAT_FIELDS.indexOf(field) >= 0) return Math.abs(a - b) < 1e-4;
  return a === b;
}

function merge(base, edits) {
  var out = {};
  Object.keys(base).forEach(function (k) { out[k] = base[k]; });
  if (edits) {
    Object.keys(edits).forEach(function (k) {
      if (EDITABLE.indexOf(k) >= 0) out[k] = edits[k];
    });
  }
  return out;
}

// Placed configs take part in the desktop layout.
function isPlaced(cfg) {
  return cfg.enabled && !cfg.mirror;
}

function rect(cfg) {
  var size = M.logicalSize(cfg);
  return { name: cfg.name, x: cfg.x, y: cfg.y, width: size.width, height: size.height };
}

// Shift placed configs so the layout starts at 0,0.
function normalize(configs) {
  var b = M.bounds(configs.filter(isPlaced).map(rect));
  if (!b.width || (b.x === 0 && b.y === 0)) return configs;
  return configs.map(function (c) {
    return isPlaced(c) ? merge(c, { x: c.x - b.x, y: c.y - b.y }) : c;
  });
}

function nits(v) {
  return v < 0 ? "from EDID" : M.trimNumber(v, 3) + " nits";
}

function iccName(path) {
  return path ? String(path).split("/").pop() : "none";
}

function describe(b, c) {
  var lines = [];
  var res = function (x) { return x.width + "×" + x.height; };
  var num = function (label, key, fmt) {
    if (!sameField(key, b[key], c[key])) lines.push(label + " " + fmt(b[key]) + " → " + fmt(c[key]));
  };
  var plainNum = function (v) { return M.trimNumber(v, 3); };

  if (b.enabled !== c.enabled) {
    lines.push(c.enabled ? "Turn on" : "Turn off");
    if (!c.enabled) return lines;
  }
  if (b.width !== c.width || b.height !== c.height) lines.push("Resolution " + res(b) + " → " + res(c));
  if (!sameField("refresh", b.refresh, c.refresh)) lines.push("Refresh " + M.trimNumber(b.refresh, 2) + " → " + M.formatRefresh(c.refresh));
  if (!sameField("scale", b.scale, c.scale)) lines.push("Scale " + M.formatScale(b.scale) + " → " + M.formatScale(c.scale));
  if (b.transform !== c.transform) lines.push("Rotation " + M.TRANSFORMS[b.transform] + " → " + M.TRANSFORMS[c.transform]);
  if (b.mirror !== c.mirror) lines.push(c.mirror ? "Mirror " + c.mirror : "Stop mirroring " + b.mirror);
  if (isPlaced(c) && (b.x !== c.x || b.y !== c.y)) lines.push("Position " + b.x + ", " + b.y + " → " + c.x + ", " + c.y);

  if (b.cm !== c.cm) lines.push("Color " + M.colorPresetLabel(b.cm) + " → " + M.colorPresetLabel(c.cm));
  if (b.bitdepth !== c.bitdepth) lines.push(c.bitdepth === 10 ? "10-bit on" : "10-bit off");
  if (b.supports_hdr !== c.supports_hdr) lines.push("HDR support " + TRISTATE[b.supports_hdr] + " → " + TRISTATE[c.supports_hdr]);
  if (b.supports_wide_color !== c.supports_wide_color) lines.push("Wide color support " + TRISTATE[b.supports_wide_color] + " → " + TRISTATE[c.supports_wide_color]);
  if (b.sdr_eotf !== c.sdr_eotf) lines.push("SDR transfer " + b.sdr_eotf + " → " + c.sdr_eotf);
  num("SDR brightness", "sdrbrightness", plainNum);
  num("SDR saturation", "sdrsaturation", plainNum);
  num("SDR white", "sdr_max_luminance", nits);
  num("SDR black", "sdr_min_luminance", nits);
  num("Peak luminance", "max_luminance", nits);
  num("Average luminance", "max_avg_luminance", nits);
  num("Minimum luminance", "min_luminance", nits);
  if (b.icc !== c.icc) lines.push("ICC profile " + iccName(b.icc) + " → " + iccName(c.icc) + (c.icc ? "" : " (after saving)"));
  if (b.vrr !== c.vrr) lines.push("VRR " + VRR_LABELS[b.vrr] + " → " + VRR_LABELS[c.vrr]);
  return lines;
}

// [{ name, lines }] for every config that differs from its base.
function changes(bases, configs) {
  var out = [];
  configs.forEach(function (c) {
    var b = find(bases, c.name);
    if (!b) return;
    var lines = describe(b, c);
    if (lines.length) out.push({ name: c.name, lines: lines });
  });
  return out;
}

function modeString(cfg) {
  return cfg.width + "x" + cfg.height + "@" + M.trimNumber(cfg.refresh, 3);
}

// The configs an apply has to send: every changed one, plus every placed
// monitor. Monitors that sit at an automatic position (Omarchy's catch-all
// `position = "auto"`) get re-placed by Hyprland whenever another monitor gets
// an explicit rule, so the whole layout is pinned. Unchanged rules that match
// the active one exactly are skipped by Hyprland, so this costs at most one
// modeset per monitor, the first time.
function applySet(pending, changes) {
  var names = changes.map(function (c) { return c.name; });
  return pending.filter(function (c) { return names.indexOf(c.name) >= 0 || isPlaced(c); });
}

// An hl.monitor rule. Runtime rules are complete, because Hyprland merges a
// rule into an existing one of the same name, so a left-out field would keep
// its old value. Saved rules are `compact`: the file is read from scratch on
// reload, so fields at Hyprland's defaults are left out.
//
// An empty ICC path is never sent (Hyprland rejects it), so removing a
// profile only takes effect once the saved file is reloaded.
function toRule(cfg, compact) {
  if (!cfg.enabled) return { output: cfg.name, disabled: true };
  var rule = {
    output: cfg.name,
    disabled: false,
    mode: modeString(cfg),
    position: Math.round(cfg.x) + "x" + Math.round(cfg.y),
    scale: cfg.scale,
    transform: cfg.transform,
    mirror: cfg.mirror || ""
  };
  COLOR.forEach(function (k) {
    var v = cfg[k];
    if (k === "icc" && !v) return;
    if (compact && sameField(k, v, COLOR_DEFAULTS[k])) return;
    rule[k] = INT_FIELDS.indexOf(k) >= 0 ? Math.round(v) : v;
  });
  return rule;
}

function script(rules) {
  return rules.map(Lua.monitor).join("\n");
}

// Names of enabled configs whose VRR setting differs between two sets.
function vrrChanged(before, after) {
  return after.filter(function (c) {
    var b = find(before, c.name);
    return c.enabled && b && b.vrr !== c.vrr;
  }).map(function (c) { return c.name; });
}

// Hyprland ignores a rule that differs from the active one only in `vrr`
// (CMonitorRule::compare doesn't look at it). Sending this first, with a tiny
// soft-property change, makes the new rule, vrr included, the active one.
function nudged(rule) {
  var out = {};
  Object.keys(rule).forEach(function (k) { out[k] = rule[k]; });
  out.sdrsaturation = (typeof rule.sdrsaturation === "number" ? rule.sdrsaturation : 1) + 0.0001;
  return out;
}

// Omarchy's clamshell watcher re-enables a disabled laptop panel every couple of
// seconds while a laptop is docked with the lid open, so a rule alone cannot keep
// one off; its own toggle flag is the opt-out (bin/panorama-omarchy-internal).
// The flag this request wants: { name, off } for the internal panel, or null when
// there is none. `off` needs another display to stay on, which is also Omarchy's
// condition for honouring the flag.
function internalFlag(configs) {
  var panel = null;
  configs.forEach(function (c) { if (M.isInternal(c.name)) panel = c; });
  if (!panel) return null;
  var others = configs.filter(function (c) { return !M.isInternal(c.name) && c.enabled; });
  return { name: panel.name, off: !panel.enabled && others.length > 0 };
}

// Problems that would make Hyprland refuse the change or produce a broken layout.
function validate(configs) {
  var errors = [];
  var placed = configs.filter(isPlaced);
  if (!placed.length) errors.push("At least one display has to stay on without mirroring another.");
  configs.forEach(function (c) {
    if (!c.enabled) return;
    if (c.mirror) {
      var target = find(configs, c.mirror);
      if (c.mirror === c.name) errors.push(c.name + " can't mirror itself.");
      else if (!target || !target.enabled) errors.push(c.name + " mirrors " + c.mirror + ", which is off.");
      else if (target.mirror) errors.push(c.name + " mirrors " + c.mirror + ", which is itself a mirror.");
    }
    if (!S.isValid(c.width, c.height, c.scale)) {
      errors.push("Scale " + M.formatScale(c.scale) + " doesn't divide " + c.width + "×" + c.height
        + " evenly; try " + M.formatScale(S.nearest(c.width, c.height, c.scale)) + ".");
    }
    if (CM_PRESETS.indexOf(c.cm) < 0) errors.push(c.name + ": unknown color preset \"" + c.cm + "\".");
    if (SDR_EOTFS.indexOf(c.sdr_eotf) < 0) errors.push(c.name + ": unknown SDR transfer function \"" + c.sdr_eotf + "\".");
    if (c.icc && String(c.icc).charAt(0) !== "/") errors.push(c.name + ": the ICC profile needs an absolute path.");
    if (!(c.sdrbrightness > 0) || !(c.sdrsaturation >= 0)) errors.push(c.name + ": SDR brightness must be above 0.");
  });
  var rects = placed.map(rect);
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      if (L.overlaps(rects[i], rects[j])) errors.push(rects[i].name + " and " + rects[j].name + " overlap.");
    }
  }
  return errors;
}

// After a save, Hyprland reloads and re-applies the file. The baseline for
// checking that result is the live state from before the save, except where the
// file states something outright: `enabled`, which every saved rule carries as
// `disabled`. The rest of a saved rule is compact (fields at Hyprland's defaults
// are left out), so the live values stay the better baseline for those.
//
// Without this, saving while something outside Panorama had already undone the
// change -- Omarchy's clamshell watcher re-enabling a laptop panel -- would
// report the reload putting it right as a problem.
function expectedAfterReload(monitors, ruleOf) {
  return monitors.map(function (m) {
    var cfg = fromLive(m, monitors);
    var rule = ruleOf(m);
    return rule && rule.disabled !== undefined ? merge(cfg, { enabled: !rule.disabled }) : cfg;
  });
}

// Differences between what was requested and what Hyprland is now doing.
function verify(requested, monitors) {
  var issues = [];
  requested.forEach(function (want) {
    var mon = find(monitors, want.name);
    if (!mon) {
      issues.push(want.name + " disappeared.");
      return;
    }
    var got = fromLive(mon, monitors, null);
    if (want.enabled !== got.enabled) {
      issues.push(want.name + (want.enabled ? " is still off." : " is still on."));
      return;
    }
    if (!want.enabled) return;
    if (want.width !== got.width || want.height !== got.height || Math.abs(want.refresh - mon.refreshRate) > 0.5) {
      issues.push(want.name + " is running " + got.width + "×" + got.height + " @ " + M.formatRefresh(mon.refreshRate)
        + " instead of " + want.width + "×" + want.height + " @ " + M.formatRefresh(want.refresh) + ".");
    }
    if (!sameField("scale", want.scale, got.scale)) issues.push("Hyprland adjusted " + want.name + "'s scale to " + M.formatScale(got.scale) + ".");
    if (want.transform !== got.transform) issues.push(want.name + " is " + M.TRANSFORMS[got.transform] + " instead of " + M.TRANSFORMS[want.transform] + ".");
    if (want.mirror !== got.mirror) {
      issues.push(want.mirror ? want.name + " isn't mirroring " + want.mirror + "." : want.name + " is still mirroring.");
    } else if (isPlaced(want) && (want.x !== got.x || want.y !== got.y)) {
      issues.push("Hyprland placed " + want.name + " at " + got.x + ", " + got.y + " instead of " + want.x + ", " + want.y + ".");
    }
    // "auto" resolves to a concrete preset, and an ICC profile replaces the preset.
    if (want.cm !== "auto" && !want.icc && want.cm !== got.cm) {
      issues.push(M.isHdr(want.cm) && !M.isHdr(got.cm)
        ? want.name + " fell back to " + M.colorPresetLabel(got.cm) + ": Hyprland doesn't think it supports HDR"
          + (want.supports_hdr === 1 && want.supports_wide_color !== 1
             ? " (HDR also needs wide color support; set Wide color to On)."
             : want.supports_hdr === 1 ? "." : ". Try “Force HDR”.")
        : want.name + " shows " + M.colorPresetLabel(got.cm) + " instead of " + M.colorPresetLabel(want.cm) + ".");
    }
    if (want.bitdepth === 10 && got.bitdepth !== 10) issues.push(want.name + " stayed 8-bit: the output or driver didn't accept 10-bit.");
    if (!sameField("sdrbrightness", want.sdrbrightness, got.sdrbrightness)) issues.push(want.name + "'s SDR brightness is " + M.trimNumber(got.sdrbrightness, 3) + ".");
  });
  return issues;
}

// Hot-plug-like changes (turning outputs on/off, mirroring) make Hyprland move
// workspaces around. Put each still-enabled monitor back on the workspace it
// showed in the snapshot, the focused monitor last so focus ends up there.
function workspaceScript(snapshot, enabledNames) {
  var lines = [];
  var focused = null;
  snapshot.forEach(function (m) {
    var ws = m.activeWorkspace;
    if (enabledNames.indexOf(m.name) < 0 || !ws || !ws.name) return;
    if (m.focused) focused = ws;
    else lines.push(focusLine(ws));
  });
  if (focused) lines.push(focusLine(focused));
  return lines.join("\n");
}

function focusLine(ws) {
  var target = ws.id > 0 ? String(ws.id) : "name:" + ws.name;
  return "hl.dispatch(" + Lua.call("hl.dsp.focus", { workspace: target }) + ")";
}
