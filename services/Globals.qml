pragma Singleton
import QtQuick
import Quickshell
import "../lib/globals.js" as G

// Live values of the global display options (`hyprctl getoption`), keyed
// "section:name". Refreshed at start, on config reloads, and on request.
Singleton {
  id: root

  property var values: {
    var out = {}
    G.OPTIONS.forEach(function (o) { out[o.key] = o.default })
    return out
  }
  property bool ready: false

  function refresh() {
    var keys = G.OPTIONS.map(function (o) { return o.key })
    runner.run(["sh", "-c", "for k; do printf '%s\\t' \"$k\"; hyprctl -j getoption \"$k\" | tr -d '\\n'; echo; done", "sh"].concat(keys),
      function (code, output) {
        var next = Object.assign({}, root.values)
        output.split("\n").forEach(function (line) {
          var tab = line.indexOf("\t")
          if (tab < 0) return
          var key = line.slice(0, tab)
          try {
            next[key] = G.fromGetoption(key, JSON.parse(line.slice(tab + 1)))
          } catch (e) {}
        })
        root.values = next
        root.ready = true
      })
  }

  Command {
    id: runner
  }

  Connections {
    target: Hypr
    function onConfigReloaded() { refreshLater.restart() }
  }

  Timer {
    id: refreshLater
    interval: 300
    onTriggered: root.refresh()
  }

  Connections {
    target: Lifecycle
    function onActiveChanged() { if (Lifecycle.active) root.refresh() }
  }

  Component.onCompleted: refresh()
}
