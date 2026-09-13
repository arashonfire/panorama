// `bin/panorama --add-menu-row` and `--remove-menu-row`: puts Setup > Display
// Settings in the Omarchy menu, or takes it out, when the user asks -- nothing
// else in Panorama touches the menu file. A one-shot Quickshell config, so the
// edit is lib/menu.js, the code the tests check.
//
// PANORAMA_MENU_OP is add or remove; PANORAMA_MENU_FILE overrides the file.
// Exit status: 0 changed, 3 nothing to change, 1 not done.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/menu.js" as Menu

ShellRoot {
  id: root

  readonly property string op: Quickshell.env("PANORAMA_MENU_OP")
  readonly property string target: Quickshell.env("PANORAMA_MENU_FILE")
    || Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"

  function finish(code, message) {
    console.log("PANORAMA-MENU: " + message)
    Qt.exit(code)
  }

  function edit(raw) {
    var result = op === "add" ? Menu.addEntry(raw) : op === "remove" ? Menu.removeEntry(raw) : null
    if (!result) return finish(1, "unknown operation '" + op + "'")
    // Not from inside the load handler: FileView drops that write's `saved`.
    if (result.write) return Qt.callLater(function () { file.setText(result.text) })
    switch (result.reason) {
    case "present": return finish(3, "the Omarchy menu already has a " + Menu.ID + " row")
    case "absent": return finish(3, "there is no Panorama row in " + target)
    case "not-ours": return finish(3, "the " + Menu.ID + " row in " + target + " doesn't open the plugin, so it's yours; left alone")
    case "unreadable": return finish(1, "the Omarchy menu can't read " + target + " as it is, so it was left alone")
    default: return finish(1, "couldn't edit " + target + " without changing other rows, so it was left alone")
    }
  }

  FileView {
    id: file
    printErrors: false
    atomicWrites: true
    onLoaded: root.edit(text())
    onLoadFailed: error => {
      if (error === FileViewError.FileNotFound) root.edit("")
      else root.finish(1, "couldn't read " + path + " (error " + error + ")")
    }
    onSaved: root.finish(0, (root.op === "add" ? "added Setup > Display Settings to " : "removed Setup > Display Settings from ") + path)
    onSaveFailed: error => root.finish(1, "couldn't write " + path + " (error " + error + ")")
  }

  // Start once the engine is up, so an early finish still ends the process.
  Timer { running: true; interval: 1; onTriggered: file.path = root.target }
  Timer { running: true; interval: 10000; onTriggered: root.finish(1, "timed out") }
}
