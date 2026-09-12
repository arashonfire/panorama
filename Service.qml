// Panorama's Omarchy shell service (kind "service"), which the shell loads while
// the plugin is enabled. Its one job is the menu row: Omarchy has no install
// hook and no way for a plugin to contribute menu rows, so the first time it
// runs it adds Setup > Display Settings to the user's menu extension, once.
// A row with that id already there counts as done; so does an earlier run
// (the marker), which is why a deleted row stays deleted. A file the menu can't
// read is never touched -- see lib/menu.js.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/menu.js" as Menu

Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"

  function addRow(raw) {
    var result = Menu.addEntry(raw)
    if (result.write) {
      if (menu.path !== menu.target) return
      // Not from inside the load handler: FileView drops that write's `saved`.
      Qt.callLater(function () { menu.setText(result.text) })
    } else if (result.reason === "present") {
      done("present")
    } else {
      // Unreadable or unsupported: leave the file be, and look again next start.
      console.warn("Panorama: not adding a menu row to " + menu.path + " (" + result.reason + ")")
    }
  }

  function done(outcome) {
    marker.setText(new Date().toISOString() + " " + outcome + "\n")
  }

  FileView {
    id: marker
    path: root.stateHome + "/panorama/omarchy-menu-row"
    printErrors: false
    atomicWrites: true
    // Only a marker that is really absent means the row was never handled.
    onLoadFailed: error => { if (error === FileViewError.FileNotFound) menu.path = menu.target }
  }

  FileView {
    id: menu
    readonly property string target: root.home + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    printErrors: false
    atomicWrites: true
    // Only once the marker check has pointed this at the real file.
    onLoaded: if (path === target) root.addRow(text())
    onLoadFailed: error => { if (path === target && error === FileViewError.FileNotFound) root.addRow("") }
    onSaved: {
      console.info("Panorama: added Setup > Display Settings to " + path)
      root.done("added")
    }
    onSaveFailed: error => console.warn("Panorama: could not write " + path + " (error " + error + ")")
  }
}
