.pragma library
.import "lua.js" as Lua

// Hyprland's global display options: what they mean, the values they take and
// their defaults (src/config/values/ConfigValues.cpp, v0.56.2). Values are
// keyed "section:name" as `hyprctl getoption` uses them, and applied/saved as
// one `hl.config({ section = { name = value } })` call.

var OFF_ON_AUTO = [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Auto" }];

var OPTIONS = [
  {
    key: "misc:vrr", group: "Sync", label: "Variable refresh rate", type: "int", default: 0,
    help: "Adaptive Sync for every monitor that doesn't have its own VRR setting.",
    choices: [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Fullscreen only" }, { value: 3, label: "Fullscreen games & video" }]
  },
  {
    key: "cursor:no_break_fs_vrr", group: "Sync", label: "Cursor keeps fullscreen VRR", type: "int", default: 2,
    help: "Don't draw new frames just because the cursor moved while a fullscreen app runs with VRR.",
    choices: OFF_ON_AUTO
  },
  {
    key: "general:allow_tearing", group: "Sync", label: "Allow tearing", type: "bool", default: false,
    help: "Master switch that lets windows asking for it (the `immediate` window rule) skip vsync for lower latency."
  },
  {
    key: "render:direct_scanout", group: "Rendering", label: "Direct scanout", type: "int", default: 0,
    help: "Let a fullscreen app go straight to the display, skipping compositing. Lower latency; can glitch on some drivers.",
    choices: [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Auto (games)" }]
  },
  {
    key: "cursor:no_hardware_cursors", group: "Rendering", label: "Software cursor", type: "int", default: 2,
    help: "Draw the cursor in software instead of on a hardware plane. Auto picks software where hardware cursors misbehave.",
    choices: [{ value: 0, label: "Off (hardware)" }, { value: 1, label: "On (software)" }, { value: 2, label: "Auto" }]
  },
  {
    key: "render:cm_enabled", group: "Color", label: "Color management", type: "bool", default: true, restart: true,
    help: "Hyprland's color-management pipeline, needed for HDR and wide gamut. Takes full effect after restarting Hyprland."
  },
  {
    key: "render:cm_auto_hdr", group: "Color", label: "Auto HDR in fullscreen", type: "int", default: 1,
    help: "Switch a monitor to HDR while a fullscreen app shows HDR content.",
    choices: [{ value: 0, label: "Off" }, { value: 1, label: "HDR" }, { value: 2, label: "HDR (EDID primaries)" }]
  },
  {
    key: "render:cm_sdr_eotf", group: "Color", label: "SDR transfer function", type: "string", default: "default",
    help: "How SDR content is mapped. A monitor's own SDR transfer setting overrides this.",
    choices: [{ value: "default", label: "Default" }, { value: "auto", label: "Auto" }, { value: "srgb", label: "sRGB" },
              { value: "gamma22", label: "Gamma 2.2" }, { value: "gamma22force", label: "Gamma 2.2 (forced)" }]
  },
  {
    key: "quirks:prefer_hdr", group: "Color", label: "Prefer HDR", type: "int", default: 0,
    help: "Tell apps that HDR is preferred, for apps that wait for that hint.",
    choices: [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Gamescope only" }]
  },
  {
    key: "render:non_shader_cm", group: "Color", label: "Hardware color pipeline", type: "int", default: 3,
    help: "Do color management in the display hardware instead of shaders when possible.",
    choices: [{ value: 0, label: "Off" }, { value: 1, label: "Always" }, { value: 2, label: "On demand" }, { value: 3, label: "Ignore" }]
  },
  {
    key: "render:icc_vcgt_enabled", group: "Color", label: "ICC calibration curves", type: "bool", default: true,
    help: "Send the calibration curves (VCGT) of a monitor's ICC profile to the display hardware."
  }
];

function option(key) {
  for (var i = 0; i < OPTIONS.length; i++) {
    if (OPTIONS[i].key === key) return OPTIONS[i];
  }
  return null;
}

// The value from `hyprctl getoption <key> -j`: { "int": 0 } / { "bool": true } / { "str": "…" }.
function fromGetoption(key, json) {
  var opt = option(key);
  if (!opt || !json) return opt ? opt.default : null;
  if (opt.type === "bool") return "bool" in json ? !!json.bool : !!json.int;
  if (opt.type === "string") return "str" in json ? String(json.str) : opt.default;
  return "int" in json ? Number(json.int) : opt.default;
}

function same(a, b) {
  return a === b;
}

function label(key, value) {
  var opt = option(key);
  if (!opt) return String(value);
  if (opt.type === "bool") return value ? "On" : "Off";
  for (var i = 0; i < (opt.choices || []).length; i++) {
    if (opt.choices[i].value === value) return opt.choices[i].label;
  }
  return String(value);
}

// "Variable refresh rate Off → On" for every option that differs.
function describe(before, after) {
  var lines = [];
  Object.keys(after).forEach(function (key) {
    if (!same(before[key], after[key])) lines.push(option(key).label + " " + label(key, before[key]) + " → " + label(key, after[key]));
  });
  return lines;
}

// { "misc:vrr": 1, "render:cm_sdr_eotf": "gamma22" } → nested hl.config table,
// keys sorted so the saved line is stable.
function table(values) {
  var out = {};
  Object.keys(values).sort().forEach(function (key) {
    var path = key.split(":");
    var node = out;
    for (var i = 0; i < path.length - 1; i++) {
      node[path[i]] = node[path[i]] || {};
      node = node[path[i]];
    }
    node[path[path.length - 1]] = values[key];
  });
  return out;
}

function script(values) {
  return Object.keys(values).length ? Lua.call("hl.config", table(values)) : "";
}

// The reverse of `table`: nested (or dotted) keys back to "section:name".
function flatten(arg, prefix) {
  var out = {};
  Object.keys(arg || {}).forEach(function (key) {
    var name = (prefix ? prefix + ":" : "") + key.replace(/\./g, ":");
    var v = arg[key];
    if (v !== null && typeof v === "object" && !Array.isArray(v)) {
      var inner = flatten(v, name);
      Object.keys(inner).forEach(function (k) { out[k] = inner[k]; });
    } else {
      out[name] = v;
    }
  });
  return out;
}
