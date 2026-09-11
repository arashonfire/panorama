const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const S = load("lib/scale.js");
const close = (a, b) => Math.abs(a - b) < 1e-9;

test("isValid: whole-pixel logical size in 1/120 steps", () => {
  assert.equal(S.isValid(2560, 1600, 1.6), true);
  assert.equal(S.isValid(2560, 1600, 1.6000000238418579), true);
  assert.equal(S.isValid(2560, 1600, 4 / 3), true);
  assert.equal(S.isValid(2560, 1600, 1.333333), true);
  assert.equal(S.isValid(2560, 1600, 1.5), false);
  assert.equal(S.isValid(1920, 1080, 1.5), true);
  assert.equal(S.isValid(1920, 1080, 1.75), false);
  assert.equal(S.isValid(1920, 1080, 1.01), false);
});

test("nearest follows Hyprland's search", () => {
  assert.ok(close(S.nearest(2560, 1600, 1.5), 1.6));
  assert.ok(close(S.nearest(1920, 1080, 1.33), 4 / 3));
  assert.ok(close(S.nearest(1920, 1080, 1.5), 1.5));
});

test("presets keep only clean values", () => {
  assert.deepEqual(Array.from(S.presets(2560, 1600), (s) => +s.toFixed(3)), [1, 1.25, 1.333, 1.6, 1.667, 2, 2.5, 4]);
  assert.deepEqual(Array.from(S.presets(1920, 1080), (s) => +s.toFixed(3)), [1, 1.25, 1.333, 1.5, 1.6, 1.667, 2, 2.5, 3, 4]);
});

test("step walks clean scales and stops at the ends", () => {
  assert.ok(close(S.step(2560, 1600, 1.6, 1), 5 / 3));
  assert.ok(close(S.step(2560, 1600, 1.6, -1), 4 / 3));
  assert.equal(S.step(2560, 1600, 4, 1), null);
  assert.equal(S.step(2560, 1600, 0.5, -1), null);
});
