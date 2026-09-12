const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const D = load("lib/draft.js");
const [edp] = require("./fixtures/monitors-edp.json");
const plain = (v) => JSON.parse(JSON.stringify(v));

const headless = {
  ...edp, id: 1, name: "PANO-1", description: "", make: "", model: "", serial: "",
  width: 1920, height: 1080, refreshRate: 60, x: 1600, y: 0, scale: 1, focused: false,
  physicalWidth: 0, physicalHeight: 0, availableModes: ["1920x1080@60.00Hz"],
  activeWorkspace: { id: 4, name: "4" }
};
const live = [edp, headless];
const base = live.map((m) => D.fromLive(m, live));
const [edpCfg, panoCfg] = base;
const LAYOUT_RULE = { output: "eDP-1", disabled: false, mode: "2560x1600@165", position: "0x0", scale: 1.6, transform: 0, mirror: "" };

test("fromLive: layout from live, color inferred without a requested rule", () => {
  assert.deepEqual(plain(edpCfg), {
    name: "eDP-1", enabled: true, width: 2560, height: 1600, refresh: 165, x: 0, y: 0, scale: 1.6, transform: 0, mirror: "",
    bitdepth: 8, cm: "srgb", sdr_eotf: "default", sdrbrightness: 1, sdrsaturation: 1, sdr_min_luminance: 0.2,
    sdr_max_luminance: 80, min_luminance: -1, max_luminance: -1, max_avg_luminance: -1, supports_hdr: 0,
    supports_wide_color: 0, icc: "", vrr: -1
  });
  assert.equal(D.fromLive({ ...headless, mirrorOf: "0" }, live).mirror, "eDP-1");
});

test("fromLive: color and VRR come from the requested rule when there is one", () => {
  // Live says sRGB (HDR fell back), the request says HDR.
  const requested = { output: "eDP-1", scale: 2, cm: "hdr", bitdepth: 10, supports_hdr: true, vrr: true };
  const cfg = D.fromLive(edp, live, requested);
  assert.equal(cfg.scale, 1.6, "layout still comes from live");
  assert.equal(cfg.cm, "hdr");
  assert.equal(cfg.bitdepth, 10);
  assert.equal(cfg.supports_hdr, 1);
  assert.equal(cfg.vrr, 1);
  assert.equal(cfg.sdrbrightness, 1, "left-out fields are Hyprland's defaults");
});

test("fromLive: what Hyprland runs beats an older request, where only a request can explain it", () => {
  // Saved rule says plain sRGB; Hyprland shows HDR from an unsaved apply.
  const liveHdr = { ...edp, colorManagementPreset: "hdr", currentFormat: "XBGR2101010", sdrMaxLuminance: 203, sdrBrightness: 1.3 };
  const cfg = plain(D.fromLive(liveHdr, [liveHdr], { output: "eDP-1" }));
  assert.equal(cfg.cm, "hdr");
  assert.equal(cfg.bitdepth, 10);
  assert.equal(cfg.supports_hdr, 1, "HDR on screen: support counts as forced on");
  assert.equal(cfg.supports_wide_color, 1);
  assert.equal(cfg.sdr_max_luminance, 203);
  assert.equal(cfg.sdrbrightness, 1.3);
  // A fallback to sRGB doesn't override the request, and auto/ICC stay as asked.
  assert.equal(D.fromLive(edp, live, { output: "eDP-1", cm: "hdr" }).cm, "hdr");
  assert.equal(D.fromLive({ ...edp, colorManagementPreset: "wide" }, live, { output: "eDP-1", cm: "auto" }).cm, "auto");
  assert.equal(D.fromLive({ ...edp, colorManagementPreset: "wide" }, live, { output: "eDP-1", icc: "/x.icc" }).cm, "srgb");
  // Without a requested rule nothing changes: everything is inferred from live.
  assert.equal(D.fromLive(liveHdr, [liveHdr]).supports_hdr, 0);
});

test("toRule: complete for runtime, compact for the file", () => {
  const complete = plain(D.toRule(edpCfg));
  const layoutOf = (rule) => Object.fromEntries(Object.keys(LAYOUT_RULE).map((k) => [k, rule[k]]));
  assert.deepEqual(layoutOf(complete), LAYOUT_RULE);
  assert.deepEqual(Object.keys(complete).slice(Object.keys(LAYOUT_RULE).length), [
    "bitdepth", "cm", "sdr_eotf", "sdrbrightness", "sdrsaturation", "sdr_min_luminance", "sdr_max_luminance",
    "min_luminance", "max_luminance", "max_avg_luminance", "supports_hdr", "supports_wide_color", "vrr"
  ], "every color/sync field is explicit");
  assert.equal(complete.vrr, -1);
  assert.equal(complete.icc, undefined, "an empty ICC path is never sent");
  assert.deepEqual(plain(D.toRule(edpCfg, true)), LAYOUT_RULE);

  const hdr = D.merge(edpCfg, { cm: "hdr", bitdepth: 10, supports_hdr: 1, sdr_max_luminance: 250.4, max_luminance: 1107, vrr: 1 });
  assert.deepEqual(plain(D.toRule(hdr, true)), { ...LAYOUT_RULE, bitdepth: 10, cm: "hdr", sdr_max_luminance: 250, max_luminance: 1107, supports_hdr: 1, vrr: 1 });
  assert.deepEqual(plain(D.toRule(D.merge(panoCfg, { enabled: false }))), { output: "PANO-1", disabled: true });
});

test("script produces one hl.monitor call per rule", () => {
  assert.equal(D.script([D.toRule(edpCfg, true)]),
    'hl.monitor({ output = "eDP-1", disabled = false, mode = "2560x1600@165", position = "0x0", scale = 1.6, transform = 0, mirror = "" })');
  assert.equal(D.script([D.toRule(D.merge(edpCfg, { scale: 4 / 3 })), D.toRule(D.merge(panoCfg, { enabled: false }))]).split("\n").length, 2);
});

test("merge ignores non-editable fields; changes describes differences", () => {
  const edited = D.merge(edpCfg, { scale: 1.25, name: "evil" });
  assert.equal(edited.name, "eDP-1");
  assert.deepEqual(plain(D.changes(base, [edited, panoCfg])), [{ name: "eDP-1", lines: ["Scale 1.6 → 1.25"] }]);
  assert.deepEqual(plain(D.changes(base, [D.merge(edpCfg, { scale: 1.6000000238 }), panoCfg])), []);
  const off = D.merge(panoCfg, { enabled: false, cm: "hdr" });
  assert.deepEqual(plain(D.changes(base, [edpCfg, off])), [{ name: "PANO-1", lines: ["Turn off"] }]);
  const rotated = D.merge(panoCfg, { transform: 1, x: 1700 });
  assert.deepEqual(plain(D.changes(base, [edpCfg, rotated]))[0].lines, ["Rotation Normal → Rotated 90°", "Position 1600, 0 → 1700, 0"]);
});

test("changes describes color and VRR edits", () => {
  const hdr = D.merge(edpCfg, {
    cm: "hdr", bitdepth: 10, supports_hdr: 1, sdrbrightness: 1.2, sdr_max_luminance: 203, max_luminance: 1107, vrr: 2, icc: "/x/panel.icc"
  });
  assert.deepEqual(plain(D.changes(base, [hdr, panoCfg]))[0].lines, [
    "Color sRGB → HDR (BT.2020, PQ)", "10-bit on", "HDR support auto → forced on", "SDR brightness 1 → 1.2",
    "SDR white 80 nits → 203 nits", "Peak luminance from EDID → 1107 nits", "ICC profile none → panel.icc",
    "VRR Use global setting → Fullscreen only"
  ]);
  const withIcc = D.merge(edpCfg, { icc: "/x/panel.icc" });
  assert.deepEqual(plain(D.changes([withIcc], [edpCfg]))[0].lines, ["ICC profile panel.icc → none (after saving)"]);
});

test("VRR changes are found and nudged", () => {
  const on = D.merge(edpCfg, { vrr: 1 });
  assert.deepEqual(plain(D.vrrChanged(base, [on, panoCfg])), ["eDP-1"]);
  assert.deepEqual(plain(D.vrrChanged(base, base)), []);
  const rule = D.toRule(on);
  const n = plain(D.nudged(rule));
  assert.ok(Math.abs(n.sdrsaturation - 1.0001) < 1e-9);
  assert.equal(n.vrr, 1);
  assert.equal(rule.sdrsaturation, 1, "original rule untouched");
});

test("applySet pins every placed monitor alongside the changed ones", () => {
  const offChanged = [edpCfg, D.merge(panoCfg, { enabled: false })];
  const names = (list) => plain(list).map((c) => c.name);
  assert.deepEqual(names(D.applySet(offChanged, D.changes(base, offChanged))), ["eDP-1", "PANO-1"]);
  const scaled = [edpCfg, D.merge(panoCfg, { scale: 1.5 })];
  assert.deepEqual(names(D.applySet(scaled, D.changes(base, scaled))), ["eDP-1", "PANO-1"]);
  const alreadyOff = [edpCfg, D.merge(panoCfg, { enabled: false })];
  assert.deepEqual(names(D.applySet(alreadyOff, [])), ["eDP-1"], "unchanged monitors that are off stay out");
});

test("normalize moves the layout to 0,0", () => {
  const moved = [D.merge(edpCfg, { x: 1920 }), D.merge(panoCfg, { x: 0, y: -200 })];
  const out = plain(D.normalize(moved));
  assert.deepEqual(out.map((c) => [c.name, c.x, c.y]), [["eDP-1", 1920, 200], ["PANO-1", 0, 0]]);
  assert.equal(D.normalize(base), base, "already normalised → same array");
});

test("validate", () => {
  assert.deepEqual(plain(D.validate(base)), []);
  assert.deepEqual(plain(D.validate([D.merge(edpCfg, { enabled: false }), D.merge(panoCfg, { enabled: false })])),
    ["At least one display has to stay on without mirroring another."]);
  assert.match(D.validate([D.merge(edpCfg, { scale: 1.5 }), panoCfg])[0], /Scale 1\.5 doesn't divide 2560×1600 evenly; try 1\.6/);
  assert.deepEqual(plain(D.validate([edpCfg, D.merge(panoCfg, { x: 1000 })])), ["eDP-1 and PANO-1 overlap."]);
  assert.deepEqual(plain(D.validate([D.merge(edpCfg, { enabled: false }), D.merge(panoCfg, { mirror: "eDP-1" })])),
    ["At least one display has to stay on without mirroring another.", "PANO-1 mirrors eDP-1, which is off."]);
  assert.deepEqual(plain(D.validate([D.merge(edpCfg, { cm: "hdr10", sdr_eotf: "pq", icc: "panel.icc" }), panoCfg])), [
    'eDP-1: unknown color preset "hdr10".', 'eDP-1: unknown SDR transfer function "pq".', "eDP-1: the ICC profile needs an absolute path."
  ]);
});

// Omarchy's watcher re-enables a laptop panel disabled without its toggle flag,
// so the flag has to follow the request exactly.
test("internalFlag tracks the laptop panel", () => {
  assert.deepEqual(plain(D.internalFlag(base)), { name: "eDP-1", off: false }, "panel on: Omarchy keeps it");
  assert.deepEqual(plain(D.internalFlag([D.merge(edpCfg, { enabled: false }), panoCfg])),
    { name: "eDP-1", off: true }, "panel off with another display on");
  assert.deepEqual(plain(D.internalFlag([D.merge(edpCfg, { enabled: false }), D.merge(panoCfg, { enabled: false })])),
    { name: "eDP-1", off: false }, "nothing else on: not Omarchy's case, and validate refuses it anyway");
  assert.deepEqual(plain(D.internalFlag([panoCfg])), null, "no laptop panel");
  // A mirroring external still counts as on: the panel is not the only output.
  assert.deepEqual(plain(D.internalFlag([D.merge(edpCfg, { enabled: false }), D.merge(panoCfg, { mirror: "eDP-1" })])),
    { name: "eDP-1", off: true });
});

// The check after a save must trust the file over a live state that something
// outside Panorama had already undone.
test("expectedAfterReload takes enabled from the saved rule", () => {
  const off = { output: "eDP-1", disabled: true };
  const names = (list) => plain(list).map((c) => [c.name, c.enabled]);
  assert.deepEqual(names(D.expectedAfterReload(live, () => null)), [["eDP-1", true], ["PANO-1", true]], "no rule: live as it is");
  assert.deepEqual(names(D.expectedAfterReload(live, (m) => (m.name === "eDP-1" ? off : null))),
    [["eDP-1", false], ["PANO-1", true]], "the file says off, though the panel was on");
  // A rule that says nothing about `disabled` leaves the live value alone.
  assert.deepEqual(names(D.expectedAfterReload(live, () => ({ output: "eDP-1", scale: 1.6 }))),
    [["eDP-1", true], ["PANO-1", true]]);
  // Everything else still comes from the live state.
  assert.equal(plain(D.expectedAfterReload(live, () => off))[0].scale, 1.6);
  assert.deepEqual(plain(D.verify(D.expectedAfterReload(live, (m) => (m.name === "eDP-1" ? off : null)),
    [{ ...edp, disabled: true }, headless])), [], "a reload that turns it off is no longer an issue");
});

test("verify reports what Hyprland did differently", () => {
  assert.deepEqual(plain(D.verify([edpCfg], live)), []);
  assert.deepEqual(plain(D.verify([D.merge(edpCfg, { scale: 1.25 })], live)), ["Hyprland adjusted eDP-1's scale to 1.6."]);
  assert.deepEqual(plain(D.verify([D.merge(panoCfg, { x: 2000 })], live)), ["Hyprland placed PANO-1 at 1600, 0 instead of 2000, 0."]);
  assert.deepEqual(plain(D.verify([D.merge(panoCfg, { enabled: false })], live)), ["PANO-1 is still on."]);
  assert.deepEqual(plain(D.verify([{ ...edpCfg, name: "DP-9" }], live)), ["DP-9 disappeared."]);
});

test("verify catches an HDR fallback and a refused 10-bit", () => {
  const issues = plain(D.verify([D.merge(edpCfg, { cm: "hdr", bitdepth: 10 })], live));
  assert.deepEqual(issues, [
    "eDP-1 fell back to sRGB: Hyprland doesn't think it supports HDR. Try “Force HDR”.",
    "eDP-1 stayed 8-bit: the output or driver didn't accept 10-bit."
  ]);
  // Forcing HDR alone isn't enough: Hyprland's supportsHDR() requires wide color.
  assert.match(D.verify([D.merge(edpCfg, { cm: "hdr", supports_hdr: 1 })], live)[0], /also needs wide color support/);
  assert.deepEqual(plain(D.verify([D.merge(edpCfg, { cm: "auto" })], live)), [], "auto resolves to a concrete preset");
  const hdrLive = [{ ...edp, colorManagementPreset: "hdr", currentFormat: "XBGR2101010" }];
  assert.deepEqual(plain(D.verify([D.merge(edpCfg, { cm: "hdr", bitdepth: 10 })], hdrLive)), []);
});

test("workspaceScript restores enabled monitors, focused one last", () => {
  const script = D.workspaceScript(live, ["eDP-1", "PANO-1"]);
  assert.equal(script, 'hl.dispatch(hl.dsp.focus({ workspace = "4" }))\nhl.dispatch(hl.dsp.focus({ workspace = "1" }))');
  assert.equal(D.workspaceScript(live, ["eDP-1"]), 'hl.dispatch(hl.dsp.focus({ workspace = "1" }))');
  const named = [{ ...edp, activeWorkspace: { id: -1337, name: 'odd "name"' } }];
  assert.equal(D.workspaceScript(named, ["eDP-1"]), 'hl.dispatch(hl.dsp.focus({ workspace = "name:odd \\"name\\"" }))');
});
