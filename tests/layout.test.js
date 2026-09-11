const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const L = load("lib/layout.js");
const plain = (v) => JSON.parse(JSON.stringify(v));

const a = { name: "A", x: 0, y: 0, width: 1600, height: 1000 };
const sized = (x, y) => ({ name: "B", x, y, width: 1920, height: 1080 });

test("overlaps and touches", () => {
  assert.equal(L.overlaps(a, sized(1600, 0)), false);
  assert.equal(L.overlaps(a, sized(1599, 0)), true);
  assert.equal(L.touches(a, sized(1600, 0)), true);
  assert.equal(L.touches(a, sized(0, 1000)), true);
  assert.equal(L.touches(a, sized(1600, 1000)), false, "corner only");
  assert.equal(L.touches(a, sized(1700, 0)), false, "gap");
});

test("snap pulls nearby edges together", () => {
  assert.deepEqual(plain(L.snap(sized(1610, 8), [a], 20)), { x: 1600, y: 0 });
  assert.deepEqual(plain(L.snap(sized(1610, -72), [a], 20)), { x: 1600, y: -80 }, "bottoms aligned");
  assert.deepEqual(plain(L.snap(sized(1700, 300), [a], 20)), { x: 1700, y: 300 });
});

test("settle keeps a touching position", () => {
  assert.deepEqual(plain(L.settle(sized(1600, 300), [a])), { x: 1600, y: 300 });
});

test("settle moves an overlapping rect to the nearest free side", () => {
  assert.deepEqual(plain(L.settle(sized(1200, 100), [a])), { x: 1600, y: 100 });
  assert.deepEqual(plain(L.settle(sized(-300, 900), [a])), { x: -300, y: 1000 });
});

test("settle attaches a detached rect", () => {
  assert.deepEqual(plain(L.settle(sized(2000, 0), [a])), { x: 1600, y: 0 });
  // Far below: flush under A, sharing a quarter of A's width.
  assert.deepEqual(plain(L.settle(sized(2000, 5000), [a])), { x: 1200, y: 1000 });
});

test("settle with nothing else keeps the rect", () => {
  assert.deepEqual(plain(L.settle(sized(12.4, 7.6), [])), { x: 12, y: 8 });
});

test("autoPlace goes right of the rightmost", () => {
  assert.deepEqual(plain(L.autoPlace(sized(0, 0), [a])), { x: 1600, y: 0 });
  assert.deepEqual(plain(L.autoPlace(sized(0, 0), [])), { x: 0, y: 0 });
});

test("resize keeps neighbours to the right and below flush", () => {
  const right = sized(1600, 0);
  const below = { name: "C", x: 0, y: 1000, width: 1600, height: 1000 };
  const out = plain(L.resize([a, right, below], "A", 2560, 1600));
  assert.deepEqual(out.map((r) => [r.name, r.x, r.y]), [["A", 0, 0], ["B", 2560, 0], ["C", 0, 1600]]);
  assert.equal(out[0].width, 2560);
});
