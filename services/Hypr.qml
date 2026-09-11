pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../lib/monitor.js" as M

// Live monitor state from `hyprctl -j monitors all`. Quickshell's
// Hyprland.monitors is empty at startup and lacks most fields, so the JSON is
// the source of truth. It is refreshed on monitor/workspace events and also
// polled, because rules applied with `hyprctl eval` (e.g. Omarchy's scale
// hotkeys) emit no event.
Singleton {
  id: root

  property var monitors: []
  property bool ready: false
  property string error: ""
  property string version: ""
  property date updatedAt: new Date()

  property string _raw: ""
  property bool _again: false

  // Hyprland re-read its config files, which drops every eval-applied rule.
  signal configReloaded()

  function refresh() {
    if (query.running) {
      _again = true
      return
    }
    query.running = true
  }

  function byName(name) {
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name === name) return monitors[i]
    }
    return null
  }

  // 1-based number shown on canvas tiles and identify overlays.
  function numberOf(name) {
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name === name) return i + 1
    }
    return 0
  }

  function _ingest(text) {
    if (!text) return
    updatedAt = new Date()
    if (text === _raw) return
    try {
      monitors = M.sortMonitors(JSON.parse(text))
      _raw = text
      error = ""
      ready = true
    } catch (e) {
      error = "Could not parse hyprctl output: " + e
    }
  }

  Process {
    id: query
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      onStreamFinished: root._ingest(text)
    }
    stderr: StdioCollector {
      id: queryErr
    }
    onExited: exitCode => {
      if (exitCode !== 0) root.error = "hyprctl failed (" + exitCode + "): " + queryErr.text.trim()
      if (root._again) {
        root._again = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    running: true
    command: ["hyprctl", "-j", "version"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.version = JSON.parse(text).tag || ""
        } catch (e) {}
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (name === "configreloaded") root.configReloaded()
      if (name.indexOf("monitor") === 0 || name.indexOf("focusedmon") === 0
          || name.indexOf("workspace") === 0 || name === "configreloaded")
        debounce.restart()
    }
  }

  Timer {
    id: debounce
    interval: 120
    onTriggered: root.refresh()
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
