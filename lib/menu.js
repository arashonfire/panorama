.pragma library

// The Omarchy menu row that opens the Panorama plugin (Setup > Display
// Settings) in the user's menu extension,
// ~/.config/omarchy/extensions/omarchy-menu.jsonc -- added and removed only
// when the user asks (`bin/panorama --add-menu-row`, `--remove-menu-row`).
//
// That file is the only way into the Omarchy menu, and the menu reads it
// all-or-nothing: once it stops parsing, every row the user added disappears,
// with no error. So an edit is offered only when the result reads the way the
// menu reads it, with every other row unchanged and in order.

var ID = "setup.panorama"
var PLUGIN_ID = "com.arashlab.panorama"

var COMMENT = "// Panorama (Omarchy shell plugin): display settings."
  + " Added by `bin/panorama --add-menu-row`; `--remove-menu-row` takes it out."

var ENTRY = {
  icon: "\u{f0379}",
  label: "Display Settings",
  description: "Panorama: monitors, HDR, VRR, brightness, profiles",
  aliases: ["panorama"],
  // Hidden once the plugin is removed. A file test, so the menu's batched
  // guards stay fork-free.
  when: "[[ -f ~/.config/omarchy/plugins/" + PLUGIN_ID + "/manifest.json ]]",
  action: "omarchy-shell shell summon " + PLUGIN_ID
}

// How the menu reads the file (shell/plugins/menu/MenuModel.js): whole-line
// `//` comments dropped and trailing commas allowed, nothing more.
function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

// The rows the menu would see, keyed by id, or null when it would see none
// because the file doesn't parse. An empty file is readable and has no rows.
function rows(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return {}
  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return null
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null
  var items = parsed.items
  return items && typeof items === "object" && !Array.isArray(items) ? items : parsed
}

// { write: true, text } with the row added, or { write: false, reason }:
// "present" when a row with our id is already there (the user's own, say),
// "unreadable" when the menu can't read the file now (not ours to touch), and
// "unsupported" when the edit wouldn't come out exactly right.
function addEntry(raw) {
  raw = raw === undefined || raw === null ? "" : String(raw)
  var before = rows(raw)
  if (before === null) return { write: false, reason: "unreadable" }
  if (Object.prototype.hasOwnProperty.call(before, ID)) return { write: false, reason: "present" }

  var row = "  " + COMMENT + "\n  " + JSON.stringify(ID) + ": " + JSON.stringify(ENTRY) + "\n"
  var text
  if (!stripJsonc(raw).trim()) {
    text = "{\n" + row + "}\n"
  } else {
    var close = raw.lastIndexOf("}")
    if (close < 0) return { write: false, reason: "unsupported" }
    var lines = raw.slice(0, close).replace(/\s+$/, "").split("\n")
    // The row before ours needs a comma unless it has one, or there is none.
    var last = stripJsonc(lines.join("\n")).replace(/\s+$/, "").slice(-1)
    if (last !== "{" && last !== ",") {
      for (var i = lines.length - 1; i >= 0; i--) {
        if (!lines[i].trim() || /^\s*\/\//.test(lines[i])) continue
        lines[i] = lines[i].replace(/\s+$/, "") + ","
        break
      }
    }
    text = lines.join("\n") + "\n\n" + row + raw.slice(close)
  }

  return checked(before, text, Object.keys(before).concat([ID]))
}

// Whether a row is the one this plugin adds: it opens the plugin. A row of the
// user's own under the same id (running `panorama`, say) is theirs to keep.
function isOurs(row) {
  return !!row && typeof row === "object" && row.action === ENTRY.action
}

// { write: true, text } with our row and its comment taken out, or
// { write: false, reason }: "absent", "not-ours" (a row under our id that
// doesn't open the plugin), "unreadable" or "unsupported", as for addEntry.
// A comma added to the row before ours stays: the menu allows a trailing one.
function removeEntry(raw) {
  raw = raw === undefined || raw === null ? "" : String(raw)
  var before = rows(raw)
  if (before === null) return { write: false, reason: "unreadable" }
  if (!Object.prototype.hasOwnProperty.call(before, ID)) return { write: false, reason: "absent" }
  if (!isOurs(before[ID])) return { write: false, reason: "not-ours" }

  var lines = raw.split("\n")
  var at = -1
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim().indexOf(JSON.stringify(ID) + ":") !== 0) continue
    if (at >= 0) return { write: false, reason: "unsupported" }
    at = i
  }
  if (at < 0) return { write: false, reason: "unsupported" }
  var from = at
  if (from > 0 && lines[from - 1].trim() === COMMENT) from--
  if (from > 0 && !lines[from - 1].trim()) from--
  lines.splice(from, at - from + 1)

  return checked(before, lines.join("\n"), Object.keys(before).filter(function (k) { return k !== ID }))
}

// `text` as the edit to write if the menu would read exactly `keys` from it,
// in that order, each row as it was in `before` (ours as ENTRY).
function checked(before, text, keys) {
  var after = rows(text)
  // A result the menu can't read is never right, even when no rows are left.
  if (after === null) return { write: false, reason: "unsupported" }
  var afterKeys = Object.keys(after)
  if (afterKeys.length !== keys.length) return { write: false, reason: "unsupported" }
  for (var k = 0; k < keys.length; k++) {
    var want = Object.prototype.hasOwnProperty.call(before, keys[k]) ? before[keys[k]] : ENTRY
    if (afterKeys[k] !== keys[k] || JSON.stringify(after[keys[k]]) !== JSON.stringify(want))
      return { write: false, reason: "unsupported" }
  }
  return { write: true, text: text }
}
