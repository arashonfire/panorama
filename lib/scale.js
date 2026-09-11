.pragma library

// Hyprland only keeps scales that give a whole-pixel logical size. It works in
// steps of 1/120 (wp_fractional_scale) and silently snaps anything else to a
// nearby clean value (Monitor.cpp), so the UI only offers clean scales.
// s = k/120 is clean when k divides both width*120 and height*120.

var MIN = 0.5;
var MAX = 4;
var PRESETS = [1, 1.25, 4 / 3, 1.5, 1.6, 5 / 3, 1.75, 2, 2.25, 2.5, 3, 4];

function cleanStep(width, height, k) {
  return k > 0 && (width * 120) % k === 0 && (height * 120) % k === 0;
}

function isValid(width, height, scale) {
  var k = Math.round(scale * 120);
  return Math.abs(scale * 120 - k) < 1e-3 && cleanStep(width, height, k);
}

// Hyprland's own search: the rounded step, then outward, trying up before down.
function nearest(width, height, scale) {
  var k = Math.round(scale * 120);
  if (cleanStep(width, height, k)) return k / 120;
  for (var i = 1; i < 90; i++) {
    if (cleanStep(width, height, k + i)) return (k + i) / 120;
    if (k - i > 0 && cleanStep(width, height, k - i)) return (k - i) / 120;
  }
  return Math.max(1, Math.round(scale));
}

function presets(width, height) {
  return PRESETS.filter(function (s) { return isValid(width, height, s); });
}

// The next clean scale above (dir > 0) or below (dir < 0), or null at the ends.
function step(width, height, scale, dir) {
  var inc = dir > 0 ? 1 : -1;
  for (var k = Math.round(scale * 120) + inc; k >= MIN * 120 && k <= MAX * 120; k += inc) {
    if (cleanStep(width, height, k)) return k / 120;
  }
  return null;
}
