.pragma library

// The Omarchy menu row that opens the Panorama plugin (Setup > Display
// Settings), added to the user's menu extension,
// ~/.config/omarchy/extensions/omarchy-menu.jsonc.
//
// That file is the only way into the Omarchy menu, and the menu reads it
// all-or-nothing: once it stops parsing, every row the user added disappears,
// with no error. So an edit is offered only when the result reads the way the
// menu reads it, with every existing row unchanged and in order, plus ours.

var ID = "setup.panorama"
var PLUGIN_ID = "com.arashlab.panorama"

var COMMENT = "// Panorama (Omarchy shell plugin): display settings. Added once by the plugin;"
  + " delete it and it stays deleted."

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

  var after = rows(text)
  var keys = Object.keys(before)
  if (!after || !Object.prototype.hasOwnProperty.call(after, ID)
      || Object.keys(after).length !== keys.length + 1)
    return { write: false, reason: "unsupported" }
  var afterKeys = Object.keys(after)
  for (var k = 0; k < keys.length; k++) {
    if (afterKeys[k] !== keys[k] || JSON.stringify(after[keys[k]]) !== JSON.stringify(before[keys[k]]))
      return { write: false, reason: "unsupported" }
  }
  return { write: true, text: text }
}
