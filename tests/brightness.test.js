const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const Br = load("lib/brightness.js");
const plain = (v) => JSON.parse(JSON.stringify(v));

test("parseList", () => {
  const out = plain(Br.parseList("eDP-1\tbacklight\t55\nDP-2\tddc\t30\nPANO-1\tnone\t-\n\n"));
  assert.deepEqual(out, {
    "eDP-1": { backend: "backlight", percent: 55, available: true },
    "DP-2": { backend: "ddc", percent: 30, available: true },
    "PANO-1": { backend: "none", percent: null, available: false }
  });
});

test("parseVcp: continuous and non-continuous features", () => {
  assert.deepEqual(plain(Br.parseVcp("VCP 10 C 50 100\n")), { code: "10", continuous: true, value: 50, max: 100 });
  assert.deepEqual(plain(Br.parseVcp("VCP 12 C 75 100")), { code: "12", continuous: true, value: 75, max: 100 });
  assert.deepEqual(plain(Br.parseVcp("VCP 60 SNC x0f")), { code: "60", continuous: false, value: 15 });
  assert.equal(Br.parseVcp("Display not found"), null);
});

test("parseCaps: named values, inline values, plain features", () => {
  const caps = plain(Br.parseCaps([
    "Model: U2723QE",
    "MCCS version: 2.1",
    "VCP Features:",
    "   Feature: 10 (Brightness)",
    "   Feature: 12 (Contrast)",
    "   Feature: 14 (Select color preset)",
    "      Values:",
    "         05: 6500 K",
    "         08: 9300 K",
    "         0b: User 1",
    "   Feature: 60 (Input Source)",
    "      Values:",
    "         0f: DisplayPort-1",
    "         11: HDMI-1",
    "   Feature: DC (Display Mode)",
    "      Values: 00 02 03 (interpretation unavailable)"
  ].join("\n")));
  assert.deepEqual(Object.keys(caps), ["10", "12", "14", "60", "DC"]);
  assert.equal(caps["12"].name, "Contrast");
  assert.deepEqual(caps["14"].values, [{ value: 5, label: "6500 K" }, { value: 8, label: "9300 K" }, { value: 11, label: "User 1" }]);
  assert.deepEqual(caps["60"].values, [{ value: 15, label: "DisplayPort-1" }, { value: 17, label: "HDMI-1" }]);
  assert.deepEqual(caps.DC.values.map((v) => v.value), [0, 2, 3]);
  assert.deepEqual(caps["10"].values, []);
});

test("target follows Omarchy's key steps", () => {
  assert.equal(Br.target(55, "+5%"), 60);
  assert.equal(Br.target(55, "5%-"), 50);
  assert.equal(Br.target(3, "+5%"), 4, "fine steps at the bottom");
  assert.equal(Br.target(5, "5%-"), 4);
  assert.equal(Br.target(1, "5%-"), 1, "never below 1 %");
  assert.equal(Br.target(98, "+5%"), 100);
  assert.equal(Br.target(55, "+1%"), 56);
  assert.equal(Br.target(55, "40%"), 40);
  assert.equal(Br.target(55, "0%"), 1);
  assert.equal(Br.target(55, "-10"), 45);
  assert.equal(Br.target(55, "bright"), null);
});

test("sdrStep and sdrPercent", () => {
  assert.equal(Br.sdrStep(1, "+5%"), 1.05);
  assert.equal(Br.sdrStep(1, "5%-"), 0.95);
  assert.equal(Br.sdrStep(1.98, "+5%"), 2);
  assert.equal(Br.sdrStep(0.52, "5%-"), 0.5);
  assert.equal(Br.sdrStep(1, "100%"), 2);
  assert.equal(Br.sdrStep(1, "1.2"), 1.2, "a multiplier");
  assert.equal(Br.sdrStep(1, "1.5x"), 1.5);
  assert.equal(Br.sdrStep(1, "2x"), 2);
  assert.equal(Br.sdrStep(1, "0.3"), 0.5, "clamped");
  assert.equal(Br.sdrStep(1, "nope"), null);
  assert.equal(Br.sdrPercent(0.5), 0);
  assert.equal(Br.sdrPercent(1.25), 50);
  assert.equal(Br.sdrPercent(2), 100);
});
