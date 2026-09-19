const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const load = require("./load");

const C = load("lib/hdrcal.js");
const E = load("lib/edid.js");
const plain = (v) => JSON.parse(JSON.stringify(v));
const oled = E.parse(fs.readFileSync(path.join(__dirname, "fixtures/edid-edp.txt"), "utf8"));
const tv = { luminance: { max: null, maxAverage: null, min: null } }; // LG TV: HDR10, no luminance

// Answers a test round by round; returns the finished result.
function run(test, edidPeak, answers) {
  let s = C.start(test, edidPeak);
  for (const a of answers) s = C.answer(s, a);
  assert.equal(s.done, true, "finished after " + answers.join(", "));
  return plain(s);
}

test("coarse squares follow the EDID peak, or go to 4000 nits without one", () => {
  assert.deepEqual(plain(C.start("peak", 1107.128)), {
    test: "peak", round: "coarse", limit: 1107, tiles: [225, 375, 550, 725, 875, 1000, 1050]
  });
  assert.deepEqual(plain(C.start("peak", null).tiles), [600, 800, 1000, 1200, 1500, 2000, 3000]);
  assert.equal(C.start("full", null).limit, 4000);
  assert.deepEqual(plain(C.start("black", 1107).tiles), [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2]);
});

test("answer buttons: every square, the control, and the display-altered case", () => {
  const labels = plain(C.choices(C.start("peak", null))).map((c) => c.label);
  assert.deepEqual(labels.slice(-2), ["Only the 4000 control", "Even the control shows"]);
  assert.equal(plain(C.choices(C.start("black", null))).pop().value, "none");
});

test("the laptop OLED: close enough after one round", () => {
  // 1000 still visible, 1050 gone: within an eye test's precision.
  assert.deepEqual(run("peak", 1107.128, [1050]), { test: "peak", done: true, value: 1050, note: "" });
  // Everything visible up to the control: the panel reaches the EDID's peak.
  assert.equal(run("peak", 1107.128, [1107]).value, 1107);
});

test("the LG TV: a second, finer round between the bracketing squares", () => {
  const coarse = C.answer(C.start("peak", null), 800);
  assert.deepEqual(plain(coarse), { test: "peak", round: "fine", limit: 4000, tiles: [600, 650, 700, 750, 800] });
  assert.equal(run("peak", null, [800, 700]).value, 700);
  // Nothing vanished in the fine round before the control: the top of the bracket.
  assert.equal(run("full", null, [700, 4000]).value, 700);
});

test("the first square vanishing, or only the control, still brackets a range", () => {
  assert.deepEqual(plain(C.answer(C.start("peak", null), 600).tiles), [300, 350, 400, 450, 500, 550, 600]);
  assert.deepEqual(plain(C.answer(C.start("peak", null), 4000).tiles), [3000, 3250, 3500, 3750, 4000]);
});

test("a visible control stops the test", () => {
  const r = run("peak", null, ["altered"]);
  assert.match(r.error, /HGIG/);
});

test("black level is the square before the first visible one", () => {
  assert.equal(run("black", null, [0.01]).value, 0.005);
  assert.equal(run("black", 1107, [0.002]).value, 0.001);
  assert.equal(run("black", 1107, [0.001]).value, 0.0005);
  assert.match(run("black", null, ["none"]).note, /crushes shadows/);
});

test("summary: a full-screen reading at the peak is left to the EDID", () => {
  const tvResults = { peak: run("peak", null, [800, 700]), full: run("full", null, [700, 4000]), black: run("black", null, [0.01]) };
  const s = plain(C.summarize(tvResults, tv));
  assert.deepEqual(s.fields, { max_luminance: 700, max_avg_luminance: -1, min_luminance: 0.005 });
  assert.match(s.notes[0], /left unset/);

  const laptop = plain(C.summarize({ peak: run("peak", 1107.128, [1050]), full: run("full", 1107.128, [1050, 1025]) }, oled));
  assert.deepEqual(laptop.fields, { max_luminance: 1050, max_avg_luminance: -1 });
  assert.match(laptop.notes[0], /EDID's 497 nits/);
});

test("summary: a full screen clipping clearly lower is used, and skipped tests leave fields alone", () => {
  const s = plain(C.summarize({ peak: run("peak", null, [1000, 1000]), full: run("full", null, [500, 450]) }, tv));
  assert.deepEqual(s.fields, { max_luminance: 1000, max_avg_luminance: 450 });
  assert.deepEqual(plain(C.summarize({ peak: run("peak", null, ["altered"]) }, tv).fields), {});
});

test("labels", () => {
  assert.equal(C.label("max_luminance", 700), "700 nits");
  assert.equal(C.label("min_luminance", 0.005), "0.005 nits");
  assert.equal(C.label("max_avg_luminance", -1), "from the EDID");
  assert.equal(C.label("max_avg_luminance", undefined), "not measured");
});
