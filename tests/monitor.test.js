const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const M = load("lib/monitor.js");
const [edp] = require("./fixtures/monitors-edp.json");

// Values cross the VM boundary, so compare through JSON rather than by prototype.
const plain = (value) => JSON.parse(JSON.stringify(value));

const headless = {
  ...edp,
  id: 1,
  name: "PANO-1",
  description: "",
  make: "",
  model: "",
  serial: "",
  width: 1920,
  height: 1080,
  refreshRate: 60,
  physicalWidth: 0,
  physicalHeight: 0,
  x: 1600,
  y: 0,
  scale: 1,
  focused: false,
  availableModes: ["1920x1080@60.00Hz"]
};

test("parseMode", () => {
  assert.deepEqual(plain(M.parseMode("2560x1600@165.00Hz")), { width: 2560, height: 1600, refresh: 165 });
  assert.deepEqual(plain(M.parseMode("1920x1080@59.94Hz")), { width: 1920, height: 1080, refresh: 59.94 });
  assert.equal(M.parseMode("preferred"), null);
});

test("groupModes sorts resolutions and refresh rates descending", () => {
  const groups = plain(M.groupModes(["1920x1080@60.00Hz", "2560x1600@60.00Hz", "2560x1600@165.00Hz", "1920x1080@144.00Hz", "junk"]));
  assert.deepEqual(groups, [
    { width: 2560, height: 1600, refreshes: [165, 60] },
    { width: 1920, height: 1080, refreshes: [144, 60] }
  ]);
});

test("logicalSize applies scale and rotation", () => {
  assert.deepEqual(plain(M.logicalSize(edp)), { width: 1600, height: 1000 });
  assert.deepEqual(plain(M.logicalSize({ ...edp, transform: 1 })), { width: 1000, height: 1600 });
  assert.deepEqual(plain(M.logicalSize({ ...edp, transform: 6 })), { width: 1600, height: 1000 });
  assert.deepEqual(plain(M.logicalSize({ ...edp, scale: 0 })), { width: 2560, height: 1600 });
});

test("disabled and mirroring monitors are not placed", () => {
  const disabled = { ...headless, name: "D", disabled: true };
  const mirror = { ...headless, name: "M", mirrorOf: "0" };
  assert.equal(M.isPlaced(edp), true);
  assert.equal(M.isPlaced(disabled), false);
  assert.equal(M.isPlaced(mirror), false);
  assert.deepEqual(plain(M.layoutRects([edp, disabled, mirror])).map((r) => r.name), ["eDP-1"]);
  assert.deepEqual(plain(M.sortMonitors([mirror, headless, disabled, edp])).map((m) => m.name), ["eDP-1", "PANO-1", "D", "M"]);
});

test("bounds and fit centre the layout", () => {
  const b = plain(M.bounds(M.layoutRects([edp, headless])));
  assert.deepEqual(b, { x: 0, y: 0, width: 3520, height: 1080 });

  const f = M.fit(b, 800, 400, 20);
  assert.equal(f.scale, Math.min(760 / 3520, 360 / 1080));
  // Horizontally the layout fills the padded width; vertically it is centred.
  assert.ok(Math.abs(f.x - 20) < 1e-9);
  assert.ok(Math.abs(f.y + b.height * f.scale / 2 - 200) < 1e-9);

  assert.deepEqual(plain(M.fit(M.bounds([]), 800, 400, 20)), { scale: 1, x: 400, y: 200 });
});

test("aspectRatio", () => {
  const cases = [[2560, 1600, "16:10"], [3840, 2160, "16:9"], [1366, 768, "16:9"], [3440, 1440, "21:9"],
    [2560, 1080, "21:9"], [5120, 1440, "32:9"], [2880, 1920, "3:2"], [1280, 1024, "5:4"], [1000, 300, "3.33:1"]];
  for (const [w, h, expected] of cases) assert.equal(M.aspectRatio(w, h), expected, `${w}x${h}`);
});

test("physical size and density", () => {
  const p = M.physical(edp);
  assert.equal(p.widthMm, 340);
  assert.ok(Math.abs(p.diagonalInches - 15.94) < 0.01);
  assert.ok(Math.abs(p.ppi - 189.4) < 0.2);
  assert.ok(Math.abs(p.effectivePpi - p.ppi / 1.6) < 1e-9);
  assert.equal(M.physical(headless), null);
});

test("formatting", () => {
  assert.equal(M.formatScale(1.6000000238418579), "1.6");
  assert.equal(M.formatScale(1.3333334), "1.333");
  assert.equal(M.formatRefresh(164.99899), "165 Hz");
  assert.equal(M.formatRefresh(59.94), "59.94 Hz");
  assert.equal(M.pixelFormat("XBGR2101010").bits, 10);
  assert.equal(M.pixelFormat("XRGB8888").bits, 8);
  assert.equal(M.pixelFormat("").bits, 0);
  assert.equal(M.colorPresetLabel("hdredid"), "HDR (EDID primaries, PQ)");
  assert.equal(M.colorPresetLabel("future"), "future");
  assert.equal(M.reservedLabel([28, 0, 0, 0]), "left 28 px");
  assert.equal(M.reservedLabel([0, 0, 0, 0]), "None");
  assert.equal(M.blockedLabel(["NOT_TORN", "USER"]), "Inactive (not torn, user)");
});

test("mirrorSource resolves the id to a monitor", () => {
  const mirror = { ...headless, mirrorOf: "0" };
  assert.equal(M.mirrorSource(mirror, [edp, mirror]).name, "eDP-1");
  assert.equal(M.mirrorSource(edp, [edp, mirror]), null);
});

test("displayName falls back to description, then connector", () => {
  assert.equal(M.displayName(edp), "Samsung Display Corp. ATNA60HS01-0");
  assert.equal(M.displayName({ ...headless, description: "Virtual" }), "Virtual");
  assert.equal(M.displayName(headless), "PANO-1");
});

test("tags", () => {
  assert.deepEqual(plain(M.tags(edp)), ["Focused"]);
  const hdr = { ...edp, focused: false, colorManagementPreset: "hdr", currentFormat: "XBGR2101010", vrr: true };
  assert.deepEqual(plain(M.tags(hdr)), ["HDR", "10-bit", "VRR"]);
});

test("inspectorSections", () => {
  const sections = plain(M.inspectorSections(edp, [edp]));
  assert.deepEqual(sections.map((s) => s.title), ["Display", "Mode", "Layout", "Color", "Sync & rendering", "Physical", "State"]);
  const row = (title, label) => sections.find((s) => s.title === title).rows.find((r) => r.label === label).value;
  assert.equal(row("Mode", "Resolution"), "2560 × 1600  (16:10)");
  assert.equal(row("Mode", "Available"), "2560 × 1600 @ 165, 60 Hz");
  assert.equal(row("Layout", "Logical size"), "1600 × 1000");
  assert.equal(row("Color", "Pixel format"), "XRGB8888 (8-bit)");

  const headlessSections = plain(M.inspectorSections(headless, [edp, headless]));
  assert.ok(!headlessSections.some((s) => s.title === "Physical"));
});
