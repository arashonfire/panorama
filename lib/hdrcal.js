.pragma library

// Manual HDR calibration: which squares each test pattern shows, and what the
// answers mean for Hyprland's luminance overrides. The patterns themselves are
// drawn by bin/panorama-hdr-pattern (PQ, through mpv, with Hyprland's tone
// mapping off for that window).
//
//   peak   Squares inside frames at the clip level. The display clips alike
//          everything above its peak, so the first square that vanishes is
//          the peak: `max_luminance`.
//   full   The same with the whole screen at the clip level:
//          `max_avg_luminance`, but only when it clips clearly below `peak`.
//          Otherwise the display dims a bright screen as a whole (ABL), which
//          an eye test can't measure, and the EDID's value stands.
//   black  Near-black squares on black. The first one that shows is just
//          above the black level: `min_luminance` is the one before it.
//
// The clip level is the EDID's peak, or 4000 nits when the EDID has none (both
// tried on real displays). The last tile of `peak` and `full` sits at the clip
// level, identical to its surround: if it shows, the display is altering the
// picture (dynamic tone mapping, contrast "enhancement") and no reading holds.

var TESTS = ["peak", "full", "black"];
var NO_EDID_LIMIT = 4000;
var BLACK_TILES = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2];
// A gap this small between the last visible and the first vanished square is
// as close as an eye test gets (repeat readings differ by about 50 nits).
var FINE_ENOUGH = 100;
// A full-screen reading this close to the peak is the peak again.
var SAME_AS_PEAK = 0.85;

var TITLES = { peak: "Peak brightness", full: "Full-screen brightness", black: "Black level" };

// Round to steps an eye test can tell apart.
function nice(v) {
  var step = v < 200 ? 10 : v < 1000 ? 25 : v < 2000 ? 50 : 100;
  return Math.max(step, Math.round(v / step) * step);
}

function unique(list) {
  var out = [];
  list.forEach(function (v) { if (out.indexOf(v) < 0) out.push(v); });
  return out.sort(function (a, b) { return a - b; });
}

function limitFor(edidPeak) {
  return edidPeak > 0 ? Math.round(edidPeak) : NO_EDID_LIMIT;
}

// First-round squares, below the clip level (which is added as the control).
function coarseTiles(test, edidPeak) {
  if (test === "black") return BLACK_TILES.slice();
  var limit = limitFor(edidPeak);
  if (!(edidPeak > 0)) {
    return test === "peak" ? [600, 800, 1000, 1200, 1500, 2000, 3000] : [300, 500, 700, 1000, 1300, 1600, 2000];
  }
  var fractions = test === "peak" ? [0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 0.97] : [0.2, 0.3, 0.4, 0.5, 0.65, 0.8, 0.95];
  return unique(fractions.map(function (f) { return nice(limit * f); })).filter(function (v) { return v < limit; });
}

// Evenly spaced squares from `lo` to `hi`, at most eight, in steps an eye can
// tell apart.
function fineTiles(lo, hi) {
  var steps = [25, 50, 100, 250, 500];
  var step = steps[steps.length - 1];
  for (var i = 0; i < steps.length; i++) {
    if ((hi - lo) / steps[i] <= 7) { step = steps[i]; break; }
  }
  var out = [];
  for (var v = lo; v < hi; v += step) out.push(v);
  out.push(hi);
  return out;
}

// A test's first round: { test, round, limit, tiles }. `tiles` are what the
// pattern shows besides the control.
function start(test, edidPeak) {
  return { test: test, round: "coarse", limit: limitFor(edidPeak), tiles: coarseTiles(test, edidPeak) };
}

// The answer buttons for a round. `peak`/`full` ask for the first square that
// vanished, `black` for the first one that shows.
function choices(state) {
  var list = state.tiles.map(function (v) { return { value: v, label: String(v) }; });
  if (state.test === "black") return list.concat([{ value: "none", label: "None of them" }]);
  return list.concat([
    { value: state.limit, label: "Only the " + state.limit + " control" },
    { value: "altered", label: "Even the control shows" }
  ]);
}

// Next step after an answer: another round ({ round: "fine", tiles, ... }) or a
// finished test ({ done: true, value, note }, or { done: true, error }).
function answer(state, a) {
  if (a === "altered") {
    return { test: state.test, done: true, error: "The control square showed, though it is identical to its surround: the display is changing the picture itself. Turn off its dynamic tone mapping (HGIG on LG and Samsung TVs, usually in Game mode) and contrast enhancements, then run the test again." };
  }
  if (state.test === "black") return blackResult(state, a);

  var v = Number(a);
  var tiles = state.tiles;
  var i = tiles.indexOf(v);
  if (i < 0 && v !== state.limit) return state;
  if (state.round === "fine") {
    return { test: state.test, done: true, value: v === state.limit ? tiles[tiles.length - 1] : v, note: "" };
  }
  // The coarse round brackets the answer between the last square still
  // visible and the first that vanished.
  var lo = i > 0 ? tiles[i - 1] : i === 0 ? nice(tiles[0] / 2) : tiles[tiles.length - 1];
  var hi = i >= 0 ? v : state.limit;
  if (hi - lo <= FINE_ENOUGH) {
    return { test: state.test, done: true, value: hi, note: v === state.limit ? "Up to the clip level of this test." : "" };
  }
  return { test: state.test, round: "fine", limit: state.limit, tiles: fineTiles(lo, hi) };
}

function blackResult(state, a) {
  var tiles = state.tiles;
  if (a === "none") {
    return { test: "black", done: true, value: tiles[tiles.length - 1],
             note: "Nothing up to " + tiles[tiles.length - 1] + " nits showed: the display crushes shadows. Check its black level or brightness setting." };
  }
  var i = tiles.indexOf(Number(a));
  if (i < 0) return state;
  if (i === 0) return { test: "black", done: true, value: tiles[0] / 2, note: "Even the darkest square showed." };
  return { test: "black", done: true, value: tiles[i - 1], note: "" };
}

// The overrides to write from finished tests (by name). Tests not run leave
// their field alone; a full-screen reading that is really the peak again
// becomes -1, Hyprland's "from the EDID".
function summarize(results, edid) {
  var fields = {};
  var notes = [];
  var peak = results.peak && !results.peak.error ? results.peak.value : null;
  var full = results.full && !results.full.error ? results.full.value : null;
  var black = results.black && !results.black.error ? results.black.value : null;
  var lum = edid && edid.luminance ? edid.luminance : {};

  if (peak !== null) fields.max_luminance = Math.round(peak);
  if (full !== null) {
    var ref = peak !== null ? peak : lum.max;
    if (ref > 0 && full >= ref * SAME_AS_PEAK) {
      fields.max_avg_luminance = -1;
      notes.push("The full screen clipped at about the peak, so the display dims a bright screen as a whole, which an eye test can't measure. "
                 + (lum.maxAverage > 0 ? "The EDID's " + Math.round(lum.maxAverage) + " nits stays in use." : "It's left unset."));
    } else {
      fields.max_avg_luminance = Math.round(full);
    }
  }
  if (black !== null) fields.min_luminance = black;
  TESTS.forEach(function (t) {
    var r = results[t];
    if (r && r.note) notes.push(TITLES[t] + ": " + r.note);
  });
  return { fields: fields, notes: notes };
}

// "700 nits", "0.005 nits", "EDID".
function label(key, v) {
  if (v === undefined) return "not measured";
  if (v < 0) return "from the EDID";
  return (key === "min_luminance" ? String(v) : String(Math.round(v))) + " nits";
}
