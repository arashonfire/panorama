.pragma library

// Brightness helpers: reading bin/panorama-brightness and ddcutil output, and
// the step rules the brightness keys use.

// `panorama-brightness list`: "NAME<TAB>BACKEND<TAB>PERCENT" per monitor, with
// BACKEND backlight/ddc/none and PERCENT "-" when it can't be read.
function parseList(text) {
  var out = {};
  String(text || "").split("\n").forEach(function (line) {
    var f = line.split("\t");
    if (f.length < 3 || !f[0]) return;
    var percent = /^\d+$/.test(f[2]) ? Number(f[2]) : null;
    out[f[0]] = { backend: f[1], percent: percent, available: f[1] !== "none" && percent !== null };
  });
  return out;
}

// `ddcutil getvcp CODE --brief`: "VCP 10 C 50 100" (continuous: value, max) or
// "VCP 60 SNC x0f" (non-continuous: a code).
function parseVcp(text) {
  var m = /^VCP ([0-9A-Fa-f]{2}) C (\d+) (\d+)/m.exec(String(text || ""));
  if (m) return { code: m[1].toUpperCase(), continuous: true, value: Number(m[2]), max: Number(m[3]) };
  m = /^VCP ([0-9A-Fa-f]{2}) (?:SNC|CNC|NC) x([0-9A-Fa-f]+)/m.exec(String(text || ""));
  if (m) return { code: m[1].toUpperCase(), continuous: false, value: parseInt(m[2], 16) };
  return null;
}

// `ddcutil capabilities`: features by hex code, each with its name and, for
// lists such as input sources, the values the monitor offers.
function parseCaps(text) {
  var features = {};
  var current = null;
  var inValues = false;
  String(text || "").split("\n").forEach(function (line) {
    var f = /^\s*Feature:\s*([0-9A-Fa-f]{2})\s*\(([^)]*)\)/.exec(line);
    if (f) {
      current = f[1].toUpperCase();
      features[current] = { name: f[2].trim(), values: [] };
      inValues = false;
      return;
    }
    if (!current) return;
    var inline = /^\s*Values:\s*(.*)$/.exec(line);
    if (inline) {
      inValues = true;
      // "Values: 0f 11 12 (interpretation unavailable)"
      var tokens = inline[1].replace(/\(.*\)/, "").match(/\b[0-9A-Fa-f]{2}\b/g) || [];
      tokens.forEach(function (t) { features[current].values.push({ value: parseInt(t, 16), label: "0x" + t.toLowerCase() }); });
      return;
    }
    var v = /^\s+([0-9A-Fa-f]{2}):\s*(.+?)\s*$/.exec(line);
    if (inValues && v) features[current].values.push({ value: parseInt(v[1], 16), label: v[2] });
    else if (!/^\s{6,}/.test(line)) inValues = false;
  });
  return features;
}

function clampPercent(p) {
  return Math.max(1, Math.min(100, Math.round(p)));
}

// The brightness keys' steps: "+5%", "5%-" or an absolute "40%". Like Omarchy,
// ±5 steps move by 1 at or below 5 %, and nothing goes below 1 %.
function target(current, spec) {
  var s = String(spec).trim(), m;
  if ((m = /^\+(\d+)%?$/.exec(s))) {
    var up = Number(m[1]);
    return clampPercent(up === 5 && current < 5 ? current + 1 : current + up);
  }
  if ((m = /^(\d+)%-$/.exec(s)) || (m = /^-(\d+)%?$/.exec(s))) {
    var down = Number(m[1]);
    return clampPercent(down === 5 && current <= 5 ? current - 1 : current - down);
  }
  if ((m = /^(\d+)%?$/.exec(s))) return clampPercent(Number(m[1]));
  return null;
}

var SDR_MIN = 0.5;
var SDR_MAX = 2;

// The same steps applied to HDR's SDR brightness (a multiplier, 0.5–2):
// ±N % moves it by N/100, an absolute N % maps onto the range, and a
// multiplier ("1.2", "1.2x", "2x") is taken as is.
function sdrStep(value, spec) {
  var s = String(spec).trim(), m, next;
  if ((m = /^\+(\d+)%?$/.exec(s))) next = value + Number(m[1]) / 100;
  else if ((m = /^(\d+)%-$/.exec(s)) || (m = /^-(\d+)%?$/.exec(s))) next = value - Number(m[1]) / 100;
  else if ((m = /^(\d*\.\d+|\d+(?:\.\d+)?)x$/.exec(s)) || (m = /^(\d*\.\d+)$/.exec(s))) next = Number(m[1]);
  else if ((m = /^(\d+)%?$/.exec(s))) next = SDR_MIN + (SDR_MAX - SDR_MIN) * Math.min(100, Number(m[1])) / 100;
  else return null;
  return Number(Math.max(SDR_MIN, Math.min(SDR_MAX, next)).toFixed(2));
}

// SDR brightness as a 0–100 % bar for the OSD.
function sdrPercent(value) {
  return Math.round((value - SDR_MIN) / (SDR_MAX - SDR_MIN) * 100);
}
