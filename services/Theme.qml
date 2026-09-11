pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colors and type scale. Follows the active Omarchy theme when there is one
// (~/.local/state/omarchy/current/theme) and keeps these neutral defaults
// everywhere else. Corner radius mirrors Hyprland's decoration:rounding.
Singleton {
  id: root

  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"

  property color background: "#141414"
  property color surface: "#1c1c1c"
  property color foreground: "#d0d0d0"
  property color muted: "#8a8a8d"
  property color accent: "#7aa2f7"
  property color urgent: "#d35f5f"

  readonly property color border: alpha(foreground, 0.14)
  readonly property color hover: alpha(foreground, 0.08)
  readonly property color selected: alpha(accent, 0.14)

  property string fontFamily: "monospace"
  property int baseSize: 12
  property int radius: 0

  readonly property real unit: baseSize / 12
  readonly property int controlHeight: Math.round(28 * unit)

  readonly property QtObject font: QtObject {
    readonly property int caption: Math.round(root.baseSize * 0.85)
    readonly property int body: root.baseSize
    readonly property int title: Math.round(root.baseSize * 1.17)
    readonly property int heading: Math.round(root.baseSize * 1.5)
    readonly property int hero: root.baseSize * 7
  }

  readonly property QtObject space: QtObject {
    readonly property int xs: Math.round(2 * root.unit)
    readonly property int sm: Math.round(4 * root.unit)
    readonly property int md: Math.round(8 * root.unit)
    readonly property int lg: Math.round(12 * root.unit)
    readonly property int xl: Math.round(18 * root.unit)
  }

  function alpha(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  // Minimal TOML reader: `[section]` headers and `key = value` lines, flattened
  // to "section.key" -> unquoted string. Enough for colors.toml and shell.toml.
  function parseToml(text) {
    var out = {}
    var section = ""
    String(text || "").split("\n").forEach(function (line) {
      var header = line.match(/^\s*\[([^\]]+)\]\s*$/)
      if (header) {
        section = header[1].trim()
        return
      }
      var kv = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*("([^"]*)"|[^#\s]+)/)
      if (kv) out[(section ? section + "." : "") + kv[1]] = kv[3] !== undefined ? kv[3] : kv[2]
    })
    return out
  }

  function pickColor(values, keys, fallback) {
    for (var i = 0; i < keys.length; i++) {
      var v = values[keys[i]]
      if (typeof v === "string" && /^#[0-9A-Fa-f]{6}$/.test(v)) return v
    }
    return fallback
  }

  FileView {
    path: root.themeDir + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var v = root.parseToml(text())
      root.background = root.pickColor(v, ["background"], root.background)
      root.surface = root.pickColor(v, ["lighter_background"], Qt.lighter(root.background, 1.35))
      root.foreground = root.pickColor(v, ["foreground"], root.foreground)
      root.muted = root.pickColor(v, ["light_foreground"], root.alpha(root.foreground, 0.6))
      root.accent = root.pickColor(v, ["accent", "blue"], root.accent)
      root.urgent = root.pickColor(v, ["red"], root.urgent)
    }
  }

  FileView {
    path: root.themeDir + "/shell.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var size = Number(root.parseToml(text())["font.base-size"])
      if (size >= 8 && size <= 32) root.baseSize = size
    }
  }

  Process {
    running: true
    command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.radius = Math.min(10, Math.max(0, JSON.parse(text).int || 0))
        } catch (e) {}
      }
    }
  }
}
