const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const load = require("./load");

const B = load("lib/block.js");
const plain = (v) => JSON.parse(JSON.stringify(v));
const stock = fs.readFileSync(path.join(__dirname, "fixtures/omarchy-monitors.lua"), "utf8");
const [edp] = require("./fixtures/monitors-edp.json");

const dell = {
  ...edp, id: 1, name: "DP-2", description: "Dell Inc. DELL U2723QE ABC123", make: "Dell Inc.", model: "DELL U2723QE",
  serial: "ABC123", width: 3840, height: 2160, refreshRate: 60, x: 1600, y: 0, scale: 1.5, focused: false,
  availableModes: ["3840x2160@60.00Hz"]
};
const live = [edp, dell];
const EDP_LINE = 'hl.monitor({ output = "eDP-1", disabled = false, mode = "2560x1600@165", position = "0x0", scale = 1.6, transform = 0, mirror = "" })';
const DELL_LINE = 'hl.monitor({ output = "desc:Dell Inc. DELL U2723QE ABC123", disabled = false, mode = "3840x2160@60", position = "1600x0", scale = 1.5, transform = 0, mirror = "" })';

test("parse: stock Omarchy file has no section and one catch-all rule", () => {
  const p = B.parse(stock);
  assert.equal(p.hasBlock, false);
  assert.equal(p.error, "");
  // The commented-out examples in the stock file don't count.
  assert.deepEqual(plain(p.rules).map((r) => [r.output, r.where]), [["", "before"]]);
});

test("matchFor: laptop panel by port, unique external by monitor, look-alikes by port", () => {
  const p = B.parse(stock);
  assert.equal(B.matchFor(edp, live, p), "port");
  assert.equal(B.matchFor(dell, live, p), "monitor");
  const twin = { ...dell, name: "DP-3", x: 5440 };
  assert.equal(B.matchFor(dell, [edp, dell, twin], p), "port");
  assert.equal(B.matchFor({ ...dell, description: "" }, live, p), "port");
});

test("body: one complete rule per connected monitor", () => {
  assert.deepEqual(plain(B.body(live, B.parse(stock), {})), [EDP_LINE, DELL_LINE]);
  const byPort = plain(B.body(live, B.parse(stock), { "DP-2": "port" }));
  assert.match(byPort[1], /^hl\.monitor\(\{ output = "DP-2",/);
  const byMonitor = plain(B.body(live, B.parse(stock), { "eDP-1": "monitor" }));
  assert.match(byMonitor[0], /^hl\.monitor\(\{ output = "desc:Samsung Display Corp\. ATNA60HS01-0",/);
});

test("render appends once, then replaces in place and leaves the rest alone", () => {
  const lines = B.body(live, B.parse(stock), {});
  const once = B.render(stock, lines);
  assert.ok(once.startsWith(stock.trimEnd() + "\n\n-- >>> panorama"));
  assert.ok(once.endsWith("-- <<< panorama <<<\n"));
  assert.equal(B.render(once, lines), once, "idempotent");

  const tail = 'hl.monitor({ output = "HDMI-A-1", disabled = true })\n';
  const withTail = once + tail;
  const tampered = withTail.replace("scale = 1.6", "scale = 1.25");
  assert.equal(B.render(tampered, lines), withTail, "section rewritten, tail kept");
});

test("isSaved compares the rules, ignoring order", () => {
  const p = B.parse(stock);
  const lines = B.body(live, p, {});
  assert.equal(B.isSaved(lines, p), false);
  const saved = B.parse(B.render(stock, lines));
  assert.equal(B.isSaved(lines, saved), true);
  assert.equal(B.isSaved(lines.slice().reverse(), saved), true);
  assert.equal(B.isSaved(B.body([{ ...edp, scale: 2 }, dell], saved, {}), saved), false);
});

test("rules for monitors that aren't connected are kept, with their style", () => {
  const saved = B.parse(B.render(stock, B.body(live, B.parse(stock), {})));
  assert.deepEqual(plain(B.body([edp], saved, {})), [EDP_LINE, DELL_LINE]);
  assert.equal(B.matchFor(dell, live, saved), "monitor");
});

test("broken sections are refused", () => {
  assert.match(B.parse("-- >>> panorama\nx").error, /no end marker/);
  assert.match(B.parse("-- <<< panorama <<<").error, /stray/);
  assert.match(B.parse("-- >>> panorama\n-- <<< panorama\n-- >>> panorama\n-- <<< panorama").error, /two Panorama sections/);
  assert.throws(() => B.render("-- >>> panorama\n", []));
});

test("conflicts: rules after the section win, rules before it lose", () => {
  const before = 'hl.monitor({ output = "eDP-1", scale = 2 })\n';
  const after = 'hl.monitor({ output = "desc:Dell Inc. DELL U2723QE", scale = 2 })\n';
  const text = B.render(before + stock, B.body(live, B.parse(stock), {})) + after;
  assert.deepEqual(plain(B.conflicts(live, B.parse(text))).map((c) => [c.output, c.wins]), [
    ["eDP-1", false],
    ["desc:Dell Inc. DELL U2723QE", true]
  ]);
});

test("saved lines keep the requested color and VRR, not the live fallback", () => {
  // eDP-1 asked for HDR; live reads sRGB because it fell back.
  const requested = { output: "eDP-1", cm: "hdr", bitdepth: 10, supports_hdr: 1, vrr: 1 };
  const lines = plain(B.body(live, B.parse(stock), {}, (m) => (m.name === "eDP-1" ? requested : null)));
  assert.equal(lines[0], EDP_LINE.replace(' })', ', bitdepth = 10, cm = "hdr", supports_hdr = 1, vrr = 1 })'));
  // Read back from the file, the request survives.
  const saved = B.parse(B.render(stock, lines));
  assert.deepEqual(plain(B.savedRequest(edp, saved)), { ...plain(require("./load")("lib/lua.js").parseCall(lines[0]).arg) });
  assert.deepEqual(plain(B.body(live, saved, {})), lines, "without an override the saved request is used");
});

test("global options live on one hl.config line inside the section", () => {
  const globals = { "misc:vrr": 2, "render:cm_auto_hdr": 0 };
  const lines = plain(B.body(live, B.parse(stock), {}, null, globals));
  assert.equal(lines[lines.length - 1], "hl.config({ misc = { vrr = 2 }, render = { cm_auto_hdr = 0 } })");
  const saved = B.parse(B.render(stock, lines));
  assert.deepEqual(plain(B.savedGlobals(saved)), globals);
  assert.equal(B.isSaved(lines, saved), true);
  assert.equal(B.isSaved(plain(B.body(live, saved, {}, null, { "misc:vrr": 1 })), saved), false);
  assert.deepEqual(plain(B.savedGlobals(B.parse(stock))), {}, "hl.config outside the section isn't Panorama's");
});

test("profiles are written after the rules and read back", () => {
  const P = load("lib/profiles.js");
  const Lua = load("lib/lua.js");
  const how = (m) => (m.name === "eDP-1" ? "port" : "monitor");
  const table = (m) => Lua.parseCall(B.body([m], B.parse(stock), {})[0]).arg;
  const desk = P.capture("Desk", live, table, how);
  const lines = plain(B.body(live, B.parse(stock), {}, null, {}, [desk]));
  assert.deepEqual(lines.slice(0, 2), [EDP_LINE, DELL_LINE], "base rules first, as before");
  assert.ok(lines.includes("panorama_profiles({"));

  const text = B.render(stock, lines);
  const saved = B.parse(text);
  assert.equal(saved.error, "");
  assert.deepEqual(plain(saved.profiles).map((p) => p.name), ["Desk"]);
  assert.deepEqual(plain(saved.profiles[0].monitors), plain(desk.monitors));
  assert.equal(B.isSaved(lines, saved), true);
  assert.equal(B.isSaved(plain(B.body(live, saved, {}, null, {}, [{ ...desk, name: "Office" }])), saved), false, "renamed profile");
  assert.equal(B.isSaved(plain(B.body(live, saved, {}, null, {}, [])), saved), false, "removed profile");

  // The whole file is still valid Lua, and Omarchy's clamshell parser sees one eDP-1 rule.
  const { spawnSync } = require("node:child_process");
  const luac = spawnSync("luac", ["-p", "-"], { input: text, encoding: "utf8" });
  if (luac.status !== null) assert.equal(luac.status, 0, luac.stderr);
  const edpRules = text.split("\n").map((l) => l.replace(/--.*$/, "")).filter((l) => /^\s*hl\.monitor\(\{.*output\s*=\s*"eDP-1"/.test(l));
  assert.equal(edpRules.length, 1);
});

test("unreadable profiles are refused rather than overwritten", () => {
  const text = B.render(stock, [EDP_LINE]).replace("-- <<< panorama", "panorama_profiles({\n  { name = broken },\n})\n-- <<< panorama");
  const p = B.parse(text);
  assert.match(p.error, /profiles in monitors\.lua can't be read/);
  assert.equal(p.hasBlock, false);
  assert.throws(() => B.render(text, [EDP_LINE]));
});

test("Omarchy's clamshell script can read the internal panel's rule", () => {
  // JS versions of the sed expressions in omarchy-hyprland-monitor-clamshell.
  const text = B.render(stock, B.body(live, B.parse(stock), {}));
  const rules = text.split("\n").map((l) => l.replace(/--.*$/, ""));
  const line = rules.find((l) => /^\s*hl\.monitor\(\{.*output\s*=\s*"eDP-1"/.test(l));
  assert.ok(line, "rule found by connector");
  const value = (key) => {
    const m = new RegExp(`.*[{,;\\s]${key}\\s*=\\s*("[^"]*"|[^,;}\\s]+)\\s*([,;}].*)?$`).exec(line);
    return m && m[1].replace(/^"(.*)"$/, "$1");
  };
  assert.equal(value("scale"), "1.6");
  assert.equal(value("position"), "0x0");
});
