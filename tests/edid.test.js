const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const load = require("./load");

const E = load("lib/edid.js");
const plain = (v) => JSON.parse(JSON.stringify(v));
const oled = fs.readFileSync(path.join(__dirname, "fixtures/edid-edp.txt"), "utf8");

test("parses the Samsung OLED's HDR, gamut and VRR (DisplayID-embedded CTA)", () => {
  const e = plain(E.parse(oled));
  assert.equal(e.manufacturer, "SDC");
  assert.equal(e.productName, "ATNA60HS01-0");
  assert.equal(e.year, 2024);
  assert.deepEqual(e.sizeCm, { width: 34, height: 22 });
  assert.equal(e.bitsPerChannel, 10);
  assert.deepEqual(e.hdr, { pq: true, hlg: false });
  assert.equal(e.bt2020, true);
  assert.equal(e.dciP3, true);
  assert.deepEqual(e.luminance, { max: 1107.128, maxAverage: 496.743, min: 0.001 });
  assert.deepEqual(e.vrr, { min: 49, max: 165 });
});

test("summary and luminance overrides", () => {
  const e = E.parse(oled);
  assert.equal(E.summary(e), "HDR10 · 1107 nits peak · BT.2020 · 10-bit · VRR 49–165 Hz");
  assert.deepEqual(plain(E.luminanceOverrides(e)), { min_luminance: 0.001, max_luminance: 1107, max_avg_luminance: 497 });
});

test("a plain SDR monitor", () => {
  const sdr = [
    "Block 0, Base EDID:",
    "    Manufacturer: DEL",
    "    Made in: week 12 of 2022",
    "    Bits per primary color channel: 8",
    "    Display Range Limits:",
    "      Monitor ranges (GTF): 48-75 Hz V, 30-83 kHz H, max dotclock 170 MHz",
    "    Display Product Name: 'DELL P2419H'",
    "    Display Product Serial Number: 'ABC123'"
  ].join("\n");
  const e = plain(E.parse(sdr));
  assert.equal(e.productName, "DELL P2419H");
  assert.equal(e.serial, "ABC123");
  assert.equal(e.year, 2022);
  assert.deepEqual(e.hdr, { pq: false, hlg: false });
  assert.deepEqual(e.luminance, { max: null, maxAverage: null, min: null });
  assert.deepEqual(e.vrr, { min: 48, max: 75 });
  assert.equal(E.summary(E.parse(sdr)), "8-bit · VRR 48–75 Hz");
  assert.deepEqual(plain(E.luminanceOverrides(E.parse(sdr))), { min_luminance: -1, max_luminance: -1, max_avg_luminance: -1 });
});

test("not an EDID dump", () => {
  assert.equal(E.parse(""), null);
  assert.equal(E.parse("edid-decode: could not read"), null);
  assert.equal(E.summary(null), "");
});

test("supports: HDR and 10-bit from the EDID, null without one", () => {
  assert.deepEqual(plain(E.supports(E.parse(oled))), { hdr: true, tenBit: true });
  assert.deepEqual(plain(E.supports(null)), { hdr: null, tenBit: null });

  const base = (depth) => ["Block 0, Base EDID:", "    Manufacturer: BOE", depth].join("\n");
  const laptop = E.parse(base("    Bits per primary color channel: 8"));
  assert.equal(laptop.maxBpc, 8);
  assert.deepEqual(plain(E.supports(laptop)), { hdr: false, tenBit: false });

  // No stated depth: 10-bit isn't ruled out.
  const undefinedDepth = E.parse(base("    Color depth is undefined"));
  assert.equal(undefinedDepth.maxBpc, null);
  assert.deepEqual(plain(E.supports(undefinedDepth)), { hdr: false, tenBit: null });

  // HDMI monitors often say 8 in the base block and 10 in the HDMI VSDB.
  const hdmi = E.parse(base("    Bits per primary color channel: 8\n  Vendor-Specific Data Block (HDMI), OUI 00-0C-03:\n    DC_30bit\n    DC_Y444"));
  assert.equal(hdmi.maxBpc, 10);
  assert.deepEqual(plain(E.supports(hdmi)), { hdr: false, tenBit: true });

  const displayId = E.parse(base("    Bits per primary color channel: 6\n  Display Interface Features Data Block:\n    Supported bpc for RGB encoding: 6, 8, 10"));
  assert.equal(displayId.maxBpc, 10);
  assert.equal(E.parse(oled).maxBpc, 12);
});
