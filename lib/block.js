.pragma library
.import "lua.js" as Lua
.import "draft.js" as D
.import "globals.js" as G
.import "match.js" as Mt
.import "profiles.js" as P

// Panorama's section of monitors.lua: finding it, rendering it, and deciding
// how each monitor is matched. One hl.monitor rule per line, because Omarchy's
// monitor scripts (omarchy-hyprland-monitor-clamshell) read the file with sed.
// Global display options Panorama manages go on one hl.config line inside it,
// and profiles (lib/profiles.js) after that.

var BEGIN = "-- >>> panorama: managed section, edits inside are overwritten on save >>>";
var HEADER = "-- Rules for monitors that aren't connected stay here until you remove them.";
var END = "-- <<< panorama <<<";

var BEGIN_RE = /^\s*--\s*>>> panorama\b/;
var END_RE = /^\s*--\s*<<< panorama\b/;
var RULE_RE = /^\s*hl\.monitor\(\s*\{.*?\boutput\s*=\s*"((?:[^"\\]|\\.)*)"/;
var CONFIG_RE = /^\s*hl\.config\(/;

function unquote(s) {
  return s.replace(/\\(\d{1,3}|.)/g, function (_, e) {
    if (/^\d+$/.test(e)) return String.fromCharCode(parseInt(e, 10));
    return { n: "\n", r: "\r", t: "\t" }[e] || e;
  });
}

// Lines of the file, where Panorama's section is, every uncommented
// hl.monitor rule and hl.config call with its position relative to the
// section, and the section's profiles. Without a section everything counts as
// "before" it, since saving appends it at the end.
function parse(text) {
  var lines = String(text || "").split("\n");
  var begin = -1, end = -1, error = "";
  // The first problem found is the one reported.
  lines.forEach(function (line, i) {
    if (error) return;
    if (BEGIN_RE.test(line)) {
      if (begin >= 0) error = "monitors.lua has two Panorama sections (lines " + (begin + 1) + " and " + (i + 1) + ").";
      else begin = i;
    } else if (END_RE.test(line)) {
      if (begin < 0 || end >= 0) error = "monitors.lua has a stray Panorama end marker on line " + (i + 1) + ".";
      else end = i;
    }
  });
  if (!error && begin >= 0 && end < 0) error = "monitors.lua has a Panorama start marker on line " + (begin + 1) + " but no end marker.";

  var hasBlock = !error && begin >= 0 && end > begin;
  var where = function (i) { return !hasBlock ? "before" : i < begin ? "before" : i > end ? "after" : "inside"; };
  var rules = [], configs = [], code = [];
  lines.forEach(function (line, i) {
    var m = RULE_RE.exec(line);
    if (m) {
      rules.push({ output: unquote(m[1]), text: line.trim(), line: i + 1, where: where(i) });
    } else if (CONFIG_RE.test(line)) {
      var values = null;
      try {
        values = G.flatten(Lua.parseCall(line).arg);
      } catch (e) {}
      configs.push({ text: line.trim(), line: i + 1, where: where(i), values: values });
    } else if (where(i) === "inside" && i !== begin && i !== end && line.trim() && line.trim() !== HEADER) {
      code.push(line);
    }
  });

  var profiles = [];
  if (hasBlock) {
    try {
      var found = P.parse(lines.slice(begin + 1, end));
      if (found) profiles = found.profiles;
    } catch (e) {
      error = "Panorama's profiles in monitors.lua can't be read (" + e.message + ").";
    }
  }
  return { lines: lines, begin: begin, end: end, error: error, hasBlock: hasBlock && !error, rules: rules, configs: configs,
           code: code, profiles: profiles };
}

// Matching lives in lib/match.js; these names stay for existing callers.
function description(mon) { return Mt.description(mon); }
function selects(selector, mon) { return Mt.selects(selector, mon); }
function canMatchByMonitor(mon, monitors) { return Mt.canMatchByMonitor(mon, monitors); }
function selector(mon, how) { return Mt.selector(mon, how); }

function savedRule(mon, parsed) {
  var found = null;
  parsed.rules.forEach(function (r) {
    if (r.where === "inside" && selects(r.output, mon)) found = r;
  });
  return found;
}

// The saved rule as a table, i.e. what was requested for this monitor.
function savedRequest(mon, parsed) {
  var rule = savedRule(mon, parsed);
  if (!rule) return null;
  try {
    return Lua.parseCall(rule.text).arg;
  } catch (e) {
    return null;
  }
}

// Global options saved in the section, keyed "section:name".
function savedGlobals(parsed) {
  var out = {};
  parsed.configs.forEach(function (c) {
    if (c.where !== "inside" || !c.values) return;
    Object.keys(c.values).forEach(function (k) { out[k] = c.values[k]; });
  });
  return out;
}

// How a monitor is saved: "port" (connector name) or "monitor" (desc:, which
// follows it to any port). A rule already in the section keeps its style.
// Otherwise laptop panels go by port, because Omarchy's clamshell script looks
// them up by connector, and uniquely described externals go by monitor.
function matchFor(mon, monitors, parsed) {
  var existing = savedRule(mon, parsed);
  if (existing) return existing.output.indexOf("desc:") === 0 && canMatchByMonitor(mon, monitors) ? "monitor" : "port";
  if (Mt.isInternal(mon.name)) return "port";
  return canMatchByMonitor(mon, monitors) ? "monitor" : "port";
}

// The compact rule table a monitor is saved with (color and VRR from
// `requested`, which falls back to the saved rule).
function ruleTable(mon, monitors, parsed, how, requested) {
  if (requested === undefined || requested === null) requested = savedRequest(mon, parsed);
  var rule = D.toRule(D.fromLive(mon, monitors, requested), true);
  rule.output = selector(mon, how);
  return rule;
}

function howFor(mon, monitors, parsed, matchBy) {
  var how = (matchBy && matchBy[mon.name]) || matchFor(mon, monitors, parsed);
  return how === "monitor" && !canMatchByMonitor(mon, monitors) ? "port" : how;
}

// The section's lines: one compact rule per connected monitor, then the saved
// rules of monitors that aren't connected right now, unchanged, then the
// global options, then the profiles (if any) with those rules as their base.
function body(monitors, parsed, matchBy, requestedFor, globals, profiles) {
  var base = monitors.map(function (m) {
    return ruleTable(m, monitors, parsed, howFor(m, monitors, parsed, matchBy), requestedFor ? requestedFor(m) : null);
  });
  var lines = base.map(Lua.monitor);
  parsed.rules.forEach(function (r) {
    if (r.where !== "inside" || monitors.some(function (m) { return selects(r.output, m); })) return;
    lines.push(r.text);
    try {
      base.push(Lua.parseCall(r.text).arg);
    } catch (e) {}
  });
  if (globals && Object.keys(globals).length) lines.push(G.script(globals));
  return lines.concat(P.render(profiles || [], base));
}

function section(lines) {
  return [BEGIN, HEADER].concat(lines, [END]);
}

// The lines match what's in the file. Rule and hl.config lines may be in any
// order (one per monitor, one for the globals); the profiles code must match
// line for line.
function isSaved(lines, parsed) {
  if (!parsed.hasBlock) return false;
  var simple = function (l) { return RULE_RE.test(l) || CONFIG_RE.test(l); };
  var current = parsed.rules.concat(parsed.configs)
    .filter(function (r) { return r.where === "inside"; })
    .map(function (r) { return r.text; })
    .sort();
  var next = lines.filter(simple).sort();
  var nextCode = lines.filter(function (l) { return !simple(l) && l.trim(); });
  var same = function (a, b) { return a.length === b.length && a.every(function (x, i) { return x === b[i]; }); };
  return same(current, next) && same(parsed.code, nextCode);
}

// The whole file with the section replaced in place, or appended at the end.
function render(text, lines) {
  var p = parse(text);
  if (p.error) throw new Error(p.error);
  var out = p.lines.slice();
  if (p.begin >= 0 && p.end > p.begin) {
    Array.prototype.splice.apply(out, [p.begin, p.end - p.begin + 1].concat(section(lines)));
    return out.join("\n");
  }
  while (out.length && out[out.length - 1].trim() === "") out.pop();
  if (out.length) out.push("");
  return out.concat(section(lines), [""]).join("\n");
}

// Rules outside the section that match a connected monitor. Ones after the
// section win over Panorama's; ones before it are overridden by it.
function conflicts(monitors, parsed) {
  return parsed.rules.filter(function (r) {
    return r.where !== "inside" && monitors.some(function (m) { return selects(r.output, m); });
  }).map(function (r) {
    return { output: r.output, line: r.line, wins: r.where === "after" };
  });
}
