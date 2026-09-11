.pragma library

// Pure helpers for monitor objects as reported by `hyprctl -j monitors all`.
// Shared by the QML UI and the node tests (tests/load.js strips the pragma), so
// nothing in here may touch QML or Qt APIs.

var TRANSFORMS = [
  "Normal",
  "Rotated 90°",
  "Rotated 180°",
  "Rotated 270°",
  "Flipped",
  "Flipped, rotated 90°",
  "Flipped, rotated 180°",
  "Flipped, rotated 270°"
];

var COLOR_PRESETS = {
  auto: "Auto",
  srgb: "sRGB",
  dcip3: "DCI-P3",
  dp3: "Display P3",
  adobe: "Adobe RGB",
  wide: "Wide gamut (BT.2020)",
  edid: "Native (EDID primaries)",
  hdr: "HDR (BT.2020, PQ)",
  hdredid: "HDR (EDID primaries, PQ)"
};

var DASH = "—";

// "2560x1600@165.00Hz" -> { width, height, refresh }
function parseMode(text) {
  var m = /^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz$/.exec(String(text).trim());
  return m ? { width: Number(m[1]), height: Number(m[2]), refresh: Number(m[3]) } : null;
}

// Modes grouped by resolution, largest first, each with refresh rates high to low.
function groupModes(modes) {
  var groups = {};
  (modes || []).forEach(function (text) {
    var mode = parseMode(text);
    if (!mode) return;
    var key = mode.width + "x" + mode.height;
    if (!groups[key]) groups[key] = { width: mode.width, height: mode.height, refreshes: [] };
    if (groups[key].refreshes.indexOf(mode.refresh) < 0) groups[key].refreshes.push(mode.refresh);
  });
  return Object.keys(groups)
    .map(function (key) {
      var g = groups[key];
      g.refreshes.sort(function (a, b) { return b - a; });
      return g;
    })
    .sort(function (a, b) { return b.width * b.height - a.width * a.height || b.width - a.width; });
}

// Transforms 1, 3, 5 and 7 swap the axes.
function isRotated(transform) {
  return transform % 2 === 1;
}

// Size in layout (logical) pixels, as Hyprland places the monitor.
function logicalSize(mon) {
  var scale = mon.scale > 0 ? mon.scale : 1;
  var w = mon.width / scale;
  var h = mon.height / scale;
  return isRotated(mon.transform) ? { width: h, height: w } : { width: w, height: h };
}

function isMirroring(mon) {
  return !!mon.mirrorOf && mon.mirrorOf !== "none";
}

// Placed monitors take part in the desktop layout; disabled and mirroring ones don't.
function isPlaced(mon) {
  return !mon.disabled && !isMirroring(mon);
}

// Placed monitors left to right, then top to bottom; everything else after, by name.
function sortMonitors(monitors) {
  return monitors.slice().sort(function (a, b) {
    var pa = isPlaced(a), pb = isPlaced(b);
    if (pa !== pb) return pa ? -1 : 1;
    if (pa) return a.x - b.x || a.y - b.y;
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
  });
}

function layoutRects(monitors) {
  return monitors.filter(isPlaced).map(function (m) {
    var size = logicalSize(m);
    return { name: m.name, x: m.x, y: m.y, width: size.width, height: size.height };
  });
}

function bounds(rects) {
  if (!rects.length) return { x: 0, y: 0, width: 0, height: 0 };
  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  rects.forEach(function (r) {
    minX = Math.min(minX, r.x);
    minY = Math.min(minY, r.y);
    maxX = Math.max(maxX, r.x + r.width);
    maxY = Math.max(maxY, r.y + r.height);
  });
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

// Uniform scale and offset that centre bounds `b` in a view, leaving `padding`
// on every side. A point (x, y) in layout space lands at
// (fit.x + x * fit.scale, fit.y + y * fit.scale).
function fit(b, viewWidth, viewHeight, padding) {
  if (b.width <= 0 || b.height <= 0) return { scale: 1, x: viewWidth / 2, y: viewHeight / 2 };
  var availW = Math.max(1, viewWidth - 2 * padding);
  var availH = Math.max(1, viewHeight - 2 * padding);
  var s = Math.min(availW / b.width, availH / b.height);
  return {
    scale: s,
    x: (viewWidth - b.width * s) / 2 - b.x * s,
    y: (viewHeight - b.height * s) / 2 - b.y * s
  };
}

function aspectRatio(width, height) {
  if (!(width > 0 && height > 0)) return DASH;
  var r = width / height;
  // Ultrawide panels (2560x1080, 3440x1440, ...) are all sold as 21:9.
  if (r >= 2.3 && r <= 2.45) return "21:9";
  var known = [[16, 9], [16, 10], [4, 3], [5, 4], [3, 2], [1, 1], [32, 9]];
  for (var i = 0; i < known.length; i++) {
    if (Math.abs(r - known[i][0] / known[i][1]) < 0.02) return known[i][0] + ":" + known[i][1];
  }
  return trimNumber(r, 2) + ":1";
}

// Physical size and pixel density, or null when the EDID reports no size
// (headless and some virtual outputs).
function physical(mon) {
  var wmm = mon.physicalWidth, hmm = mon.physicalHeight;
  if (!(wmm > 0 && hmm > 0)) return null;
  var diagonal = Math.sqrt(wmm * wmm + hmm * hmm) / 25.4;
  var ppi = Math.sqrt(mon.width * mon.width + mon.height * mon.height) / diagonal;
  return {
    widthMm: wmm,
    heightMm: hmm,
    diagonalInches: diagonal,
    ppi: ppi,
    effectivePpi: ppi / (mon.scale > 0 ? mon.scale : 1)
  };
}

// 1.6000000238418579 -> "1.6", 164.99899 -> "165"
function trimNumber(n, digits) {
  return String(Number(Number(n).toFixed(digits)));
}

function formatScale(scale) {
  return trimNumber(scale, 3);
}

function formatRefresh(hz) {
  return trimNumber(hz, 2) + " Hz";
}

function formatResolution(width, height) {
  return width + " × " + height;
}

function pixelFormat(format) {
  var name = String(format || "");
  var bits = /2101010/.test(name) ? 10 : /16161616/.test(name) ? 16 : /8888$/.test(name) ? 8 : 0;
  return { name: name, bits: bits };
}

function colorPresetLabel(preset) {
  return COLOR_PRESETS[preset] || preset || "Unknown";
}

function isHdr(preset) {
  return preset === "hdr" || preset === "hdredid";
}

// hyprctl reports mirrorOf as the source monitor's id, not its name.
function mirrorSource(mon, monitors) {
  if (!isMirroring(mon)) return null;
  for (var i = 0; i < monitors.length; i++) {
    if (String(monitors[i].id) === String(mon.mirrorOf)) return monitors[i];
  }
  return null;
}

function displayName(mon) {
  var name = [mon.make, mon.model]
    .map(function (s) { return String(s || "").trim(); })
    .filter(function (s) { return s.length > 0; })
    .join(" ");
  return name || String(mon.description || "").trim() || mon.name;
}

// hyprctl orders the reserved area as left, top, right, bottom.
function reservedLabel(reserved) {
  if (!reserved || reserved.length !== 4) return DASH;
  var sides = ["left", "top", "right", "bottom"];
  var parts = [];
  for (var i = 0; i < 4; i++) {
    if (reserved[i]) parts.push(sides[i] + " " + reserved[i] + " px");
  }
  return parts.length ? parts.join(", ") : "None";
}

function humanize(code) {
  return String(code).toLowerCase().replace(/_/g, " ");
}

function blockedLabel(reasons) {
  if (!reasons || !reasons.length) return "Inactive";
  return "Inactive (" + reasons.map(humanize).join(", ") + ")";
}

// Short badges for the inspector header.
function tags(mon) {
  var out = [];
  if (mon.focused) out.push("Focused");
  if (mon.disabled) out.push("Disabled");
  if (isMirroring(mon)) out.push("Mirroring");
  if (isHdr(mon.colorManagementPreset)) out.push("HDR");
  if (pixelFormat(mon.currentFormat).bits === 10) out.push("10-bit");
  if (mon.vrr) out.push("VRR");
  if (mon.dpmsStatus === false) out.push("Screen off");
  return out;
}

// Everything the read-only inspector shows, as [{ title, rows: [{ label, value }] }].
function inspectorSections(mon, monitors) {
  var modes = groupModes(mon.availableModes);
  var logical = logicalSize(mon);
  var format = pixelFormat(mon.currentFormat);
  var source = mirrorSource(mon, monitors || []);
  var phys = physical(mon);
  var model = String(mon.model || "").trim();

  var sections = [
    { title: "Display", rows: [
      { label: "Connector", value: mon.name },
      { label: "Make", value: mon.make || DASH },
      { label: "Model", value: model || DASH },
      { label: "Serial", value: mon.serial || DASH },
      { label: "Description", value: mon.description || DASH }
    ] },
    { title: "Mode", rows: [
      { label: "Resolution", value: formatResolution(mon.width, mon.height) + "  (" + aspectRatio(mon.width, mon.height) + ")" },
      { label: "Refresh rate", value: formatRefresh(mon.refreshRate) },
      { label: "Available", value: modes.length ? modes.map(function (g) {
        return formatResolution(g.width, g.height) + " @ " + g.refreshes.map(function (r) { return trimNumber(r, 2); }).join(", ") + " Hz";
      }).join("\n") : DASH }
    ] },
    { title: "Layout", rows: [
      { label: "Enabled", value: mon.disabled ? "No" : "Yes" },
      { label: "Position", value: mon.x + ", " + mon.y },
      { label: "Scale", value: formatScale(mon.scale) },
      { label: "Logical size", value: formatResolution(Math.round(logical.width), Math.round(logical.height)) },
      { label: "Transform", value: TRANSFORMS[mon.transform] || String(mon.transform) },
      { label: "Mirroring", value: source ? source.name : isMirroring(mon) ? "Monitor " + mon.mirrorOf : "No" },
      { label: "Reserved", value: reservedLabel(mon.reserved) }
    ] },
    { title: "Color", rows: [
      { label: "Preset", value: colorPresetLabel(mon.colorManagementPreset) },
      { label: "Pixel format", value: format.bits ? format.name + " (" + format.bits + "-bit)" : format.name || DASH },
      { label: "SDR brightness", value: trimNumber(mon.sdrBrightness, 2) },
      { label: "SDR saturation", value: trimNumber(mon.sdrSaturation, 2) },
      { label: "SDR luminance", value: trimNumber(mon.sdrMinLuminance, 3) + " – " + trimNumber(mon.sdrMaxLuminance, 0) + " nits" }
    ] },
    { title: "Sync & rendering", rows: [
      // Hyprland's own flag; it can claim VRR is on after the driver refused it.
      { label: "VRR", value: mon.vrr ? "Active (as reported)" : "Off" },
      { label: "Tearing", value: mon.activelyTearing ? "Active" : blockedLabel(mon.tearingBlockedBy) },
      { label: "Direct scanout", value: mon.directScanoutTo && mon.directScanoutTo !== "0" ? "Active" : blockedLabel(mon.directScanoutBlockedBy) },
      { label: "Hardware cursor", value: mon.hardwareCursorsInUse ? "Yes" : "No" }
    ] }
  ];

  if (phys) {
    sections.push({ title: "Physical", rows: [
      { label: "Size", value: phys.widthMm + " × " + phys.heightMm + " mm" },
      { label: "Diagonal", value: trimNumber(phys.diagonalInches, 1) + "\"" },
      { label: "Pixel density", value: Math.round(phys.ppi) + " PPI (" + Math.round(phys.effectivePpi) + " at scale " + formatScale(mon.scale) + ")" }
    ] });
  }

  var workspace = mon.activeWorkspace && mon.activeWorkspace.name;
  var special = mon.specialWorkspace && mon.specialWorkspace.id ? mon.specialWorkspace.name : "";
  sections.push({ title: "State", rows: [
    { label: "Focused", value: mon.focused ? "Yes" : "No" },
    { label: "Power", value: mon.dpmsStatus === false ? "Off (DPMS)" : "On" },
    { label: "Workspace", value: workspace || DASH },
    { label: "Special workspace", value: special || DASH }
  ] });

  return sections;
}
