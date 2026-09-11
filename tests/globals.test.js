const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const G = load("lib/globals.js");
const Lua = load("lib/lua.js");
const plain = (v) => JSON.parse(JSON.stringify(v));

test("every option has a known type and a valid default", () => {
  for (const opt of plain(G.OPTIONS)) {
    assert.ok(["int", "bool", "string"].includes(opt.type), opt.key);
    if (opt.choices) assert.ok(opt.choices.some((c) => c.value === opt.default), `${opt.key} default is a choice`);
    assert.match(opt.key, /^[a-z]+:[a-z_]+$/);
  }
});

test("fromGetoption reads hyprctl's JSON", () => {
  assert.equal(G.fromGetoption("misc:vrr", { int: 1, set: true }), 1);
  assert.equal(G.fromGetoption("general:allow_tearing", { bool: true }), true);
  assert.equal(G.fromGetoption("render:cm_sdr_eotf", { str: "gamma22" }), "gamma22");
  assert.equal(G.fromGetoption("misc:vrr", null), 0, "falls back to the default");
});

test("script writes one nested, sorted hl.config call", () => {
  const values = { "render:cm_sdr_eotf": "gamma22", "misc:vrr": 1, "general:allow_tearing": true };
  const line = G.script(values);
  assert.equal(line, 'hl.config({ general = { allow_tearing = true }, misc = { vrr = 1 }, render = { cm_sdr_eotf = "gamma22" } })');
  assert.deepEqual(plain(G.flatten(Lua.parseCall(line).arg)), { "general:allow_tearing": true, "misc:vrr": 1, "render:cm_sdr_eotf": "gamma22" });
  assert.equal(G.script({}), "");
});

test("flatten accepts dotted keys too", () => {
  assert.deepEqual(plain(G.flatten({ "misc.vrr": 2 })), { "misc:vrr": 2 });
});

test("labels and describe", () => {
  assert.equal(G.label("misc:vrr", 3), "Fullscreen games & video");
  assert.equal(G.label("general:allow_tearing", false), "Off");
  assert.deepEqual(plain(G.describe({ "misc:vrr": 0, "general:allow_tearing": false }, { "misc:vrr": 1, "general:allow_tearing": false })),
    ["Variable refresh rate Off → On"]);
});
