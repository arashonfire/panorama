const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { execFileSync } = require("node:child_process");
const load = require("./load");

const M = load("lib/menu.js");
const plain = (v) => JSON.parse(JSON.stringify(v));

// Omarchy's own menu parser, when Omarchy is installed: the edit has to hold
// up against what the menu actually runs, not only against our reading of it.
const omarchyModel = (() => {
  const file = `${process.env.OMARCHY_PATH || "/usr/share/omarchy"}/shell/plugins/menu/MenuModel.js`;
  return fs.existsSync(file) ? require(file) : null;
})();

// Every check an edit must pass, by our rules and (if present) Omarchy's.
function assertAdded(raw) {
  const result = plain(M.addEntry(raw));
  assert.equal(result.write, true, `expected a write, got ${result.reason}`);
  const before = plain(M.rows(raw));
  const after = plain(M.rows(result.text));
  assert.deepEqual(Object.keys(after), [...Object.keys(before), M.ID]);
  for (const k of Object.keys(before)) assert.deepEqual(after[k], before[k], k);
  assert.deepEqual(after[M.ID], plain(M.ENTRY));
  if (omarchyModel) {
    const items = omarchyModel.parseMenuJsonc(result.text);
    const ours = items.find((i) => i.id === M.ID);
    assert.ok(ours, "Omarchy's parser sees the row");
    assert.equal(ours.parent, "setup");
    assert.equal(ours.kind, "action");
    assert.equal(items.length, omarchyModel.parseMenuJsonc(raw).length + 1);
  }
  // Added once: running it again on the result changes nothing.
  assert.deepEqual(plain(M.addEntry(result.text)), { write: false, reason: "present" });
  return result.text;
}

const template = `{
  // Extend the Quickshell Omarchy menu with JSONC.
  //
  // Examples:
  // "personal": {"icon":"","label":"Personal"},
  // "about": {"icon":"","label":"About","action":"omarchy-launch-or-focus-tui \\"zsh -c 'fastfetch; read -k 1'\\""},
}
`;

test("the row opens the plugin from Setup", () => {
  assert.equal(M.ID, "setup.panorama");
  assert.equal(M.ENTRY.action, "omarchy-shell shell summon com.arashlab.panorama");
  assert.equal(M.ENTRY.icon, "\u{f0379}");
  assert.match(M.ENTRY.when, /^\[\[ -f ~\/\.config\/omarchy\/plugins\/com\.arashlab\.panorama\/manifest\.json \]\]$/);
});

test("Omarchy's template: comments only, commented-out rows with braces", () => {
  const text = assertAdded(template);
  assert.ok(text.startsWith(template.slice(0, template.lastIndexOf("}"))), "everything above is kept verbatim");
  assert.match(text, /\n}\n$/);
});

test("Omarchy's installed template, when there is one", { skip: !omarchyModel }, () => {
  assertAdded(fs.readFileSync(`${process.env.OMARCHY_PATH || "/usr/share/omarchy"}/config/omarchy/extensions/omarchy-menu.jsonc`, "utf8"));
});

test("a last row without a comma gets one, on its own line", () => {
  const raw = `{
  // mine
  "personal": {"icon":"","label":"Personal"},
  "personal.notes": {"icon":"󰎞","label":"Notes","action":"omarchy-launch-editor ~/notes"}
}
`;
  const text = assertAdded(raw);
  assert.match(text, /"action":"omarchy-launch-editor ~\/notes"},\n/);
});

test("a last row that already has a trailing comma is left as it is", () => {
  const raw = `{\n  "personal": {"icon":"","label":"Personal"},\n}\n`;
  const text = assertAdded(raw);
  assert.ok(!text.includes(",,"));
});

test("a trailing comment after the last row", () => {
  assertAdded(`{\n  "personal": {"icon":"","label":"Personal"}\n  // the end\n}\n`);
});

test("strings holding // and braces are not mistaken for comments or the end", () => {
  assertAdded(`{\n  "web.docs": {"label":"Docs {v2}","action":"xdg-open https://example.org/a}b"}\n}`);
});

test("one line, no newline at the end", () => {
  assertAdded(`{"personal":{"label":"Personal"}}`);
});

test("missing or empty file: a new one with just the row", () => {
  for (const raw of ["", "   \n", undefined, null]) {
    const text = assertAdded(raw);
    assert.equal(text.split("\n")[0], "{");
  }
});

test("a row with our id already there is kept, whatever it says", () => {
  const raw = `{\n  "setup.panorama": {"icon":"󰍹","label":"Display Settings","action":"panorama"}\n}\n`;
  assert.deepEqual(plain(M.addEntry(raw)), { write: false, reason: "present" });
});

test("a file the menu can't read is not touched", () => {
  for (const raw of [
    `{\n  "a": {"label":"A"} // inline comments break the menu's parser\n}`,
    `{\n  /* block */ "a": {"label":"A"}\n}`,
    `{ "a": `,
    `[1, 2]`,
    `"text"`,
  ]) assert.deepEqual(plain(M.addEntry(raw)), { write: false, reason: "unreadable" }, raw);
});

test("the {items: ...} form is left alone rather than edited wrong", () => {
  assert.deepEqual(plain(M.addEntry(`{\n  "items": {"personal": {"label":"Personal"}}\n}\n`)), { write: false, reason: "unsupported" });
});

test("the row's guard fits the menu's batched guard script", { skip: !omarchyModel }, () => {
  const script = omarchyModel.guardScript({ [M.ID]: plain(M.ENTRY) });
  execFileSync("bash", ["-n", "-c", script]);
  const home = fs.mkdtempSync(`${require("node:os").tmpdir()}/panorama-guard-`);
  const run = () => execFileSync("bash", ["-c", script], { env: { HOME: home, PATH: process.env.PATH } }).toString().trim();
  try {
    assert.equal(run(), `${M.ID}:w:0`);
    fs.mkdirSync(`${home}/.config/omarchy/plugins/com.arashlab.panorama`, { recursive: true });
    fs.writeFileSync(`${home}/.config/omarchy/plugins/com.arashlab.panorama/manifest.json`, "{}");
    assert.equal(run(), `${M.ID}:w:1`);
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});

// Every check a removal must pass: the other rows as they were, ours gone.
function assertRemoved(raw) {
  const result = plain(M.removeEntry(raw));
  assert.equal(result.write, true, `expected a write, got ${result.reason}`);
  const before = plain(M.rows(raw));
  const after = plain(M.rows(result.text));
  assert.deepEqual(Object.keys(after), Object.keys(before).filter((k) => k !== M.ID));
  for (const k of Object.keys(after)) assert.deepEqual(after[k], before[k], k);
  if (omarchyModel) {
    const items = omarchyModel.parseMenuJsonc(result.text);
    assert.ok(!items.some((i) => i.id === M.ID), "Omarchy's parser no longer sees the row");
    assert.equal(items.length, omarchyModel.parseMenuJsonc(raw).length - 1);
  }
  assert.deepEqual(plain(M.removeEntry(result.text)), { write: false, reason: "absent" });
  return result.text;
}

test("removing what was added gives Omarchy's template back byte for byte", () => {
  assert.equal(assertRemoved(assertAdded(template)), template);
});

test("removing after a row that gained a comma leaves that comma, which the menu allows", () => {
  const raw = `{\n  "personal": {"icon":"","label":"Personal"}\n}\n`;
  assert.equal(assertRemoved(assertAdded(raw)), `{\n  "personal": {"icon":"","label":"Personal"},\n}\n`);
});

test("the row can be removed with rows added after it", () => {
  const added = assertAdded(`{\n  "personal": {"label":"Personal"}\n}\n`);
  const grown = added.replace(/(\n  "setup\.panorama": \{.*\})\n}/, '$1,\n  "personal.notes": {"label":"Notes","action":"notes"}\n}');
  const text = assertRemoved(grown);
  assert.deepEqual(Object.keys(plain(M.rows(text))), ["personal", "personal.notes"]);
});

test("a row under our id that doesn't open the plugin is the user's: never removed", () => {
  const raw = `{\n  "setup.panorama": {"icon":"󰍹","label":"Display Settings","action":"panorama"}\n}\n`;
  assert.deepEqual(plain(M.removeEntry(raw)), { write: false, reason: "not-ours" });
});

test("nothing to remove: absent, missing or empty", () => {
  for (const raw of [template, "", undefined, null])
    assert.deepEqual(plain(M.removeEntry(raw)), { write: false, reason: "absent" });
});

test("removal leaves a file the menu can't read alone", () => {
  const raw = assertAdded(template).replace("}\n", "} // inline\n");
  assert.deepEqual(plain(M.removeEntry(raw)), { write: false, reason: "unreadable" });
});

test("our row reformatted across lines is left alone rather than half removed", () => {
  const spread = assertAdded(template).replace(/("setup\.panorama": \{)/, "$1\n   ");
  assert.equal(plain(M.rows(spread))[M.ID].action, M.ENTRY.action);
  assert.deepEqual(plain(M.removeEntry(spread)), { write: false, reason: "unsupported" });
});
