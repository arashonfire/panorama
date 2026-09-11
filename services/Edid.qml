pragma Singleton
import QtQuick
import Quickshell
import "../lib/edid.js" as E

// What each connected panel advertises: `edid-decode` on every
// /sys/class/drm/card*-<connector>/edid, parsed by lib/edid.js. Re-read when
// the set of monitors changes.
Singleton {
  id: root

  property var byName: ({})
  property bool available: true
  property string _names: ""

  function refresh() {
    var script = "command -v edid-decode >/dev/null || { echo @@@MISSING; exit 0; }\n"
      // sysfs reports these files as size 0 even when they hold an EDID, so
      // no size check: edid-decode just prints "was empty" for idle ports.
      + "for f in /sys/class/drm/card*-*/edid; do\n"
      + "  c=${f%/edid}; c=${c##*/}; c=${c#card*-}\n"
      + "  printf '@@@ %s\\n' \"$c\"\n"
      + "  edid-decode \"$f\" 2>/dev/null\n"
      + "done"
    runner.run(["sh", "-c", script], function (code, output) {
      if (output.indexOf("@@@MISSING") >= 0) {
        root.available = false
        root.byName = ({})
        return
      }
      var next = {}
      output.split(/^@@@ /m).forEach(function (chunk) {
        var nl = chunk.indexOf("\n")
        if (nl < 0) return
        var parsed = E.parse(chunk.slice(nl + 1))
        if (parsed) next[chunk.slice(0, nl).trim()] = parsed
      })
      root.available = true
      root.byName = next
    })
  }

  Command {
    id: runner
  }

  // Singletons are created on first use, which can be after the monitor list
  // has settled, so read once right away too.
  Component.onCompleted: refresh()

  Connections {
    target: Hypr
    function onMonitorsChanged() {
      var names = Hypr.monitors.map(function (m) { return m.name }).sort().join(",")
      if (names === root._names) return
      root._names = names
      root.refresh()
    }
  }
}
