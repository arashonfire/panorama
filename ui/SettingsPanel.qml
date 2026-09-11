import QtQuick
import QtQuick.Layouts
import qs.services
import "../lib/monitor.js" as M
import "../lib/scale.js" as S
import "../lib/draft.js" as D

// Editors for one monitor. Edits go to the Draft; nothing reaches Hyprland
// until Apply.
ColumnLayout {
  id: root

  required property var monitor
  readonly property string name: monitor.name
  readonly property var cfg: Draft.config(name) || D.fromLive(monitor, Hypr.monitors)
  readonly property var base: Draft.baseOf(name) || cfg
  readonly property var groups: M.groupModes(monitor.availableModes)
  readonly property var group: groups.find(function (g) { return g.width === root.cfg.width && g.height === root.cfg.height }) || null
  readonly property var targets: Draft.configs.filter(function (c) { return c.name !== root.name && c.enabled && !c.mirror })
  readonly property var logical: M.logicalSize(cfg)
  readonly property int labelIndent: 3 + Math.round(96 * Theme.unit) + 2 * Theme.space.md

  spacing: Theme.space.lg
  enabled: Apply.state === "idle"

  SettingRow {
    label: "Enabled"
    changed: root.cfg.enabled !== root.base.enabled
    Toggle {
      label: "Enabled"
      checked: root.cfg.enabled
      onToggled: Draft.setEnabled(root.name, !root.cfg.enabled)
    }
    Item { Layout.fillWidth: true }
  }

  // In HDR the panel ignores its backlight; brightness is then how bright
  // ordinary (SDR) content is, Hyprland's sdrbrightness, applied at once like
  // the brightness keys (what Windows calls SDR content brightness).
  readonly property bool liveHdr: M.isHdr(monitor.colorManagementPreset)

  SettingRow {
    visible: root.cfg.enabled
    label: root.liveHdr ? "SDR brightness" : "Brightness"
    Slider {
      Layout.fillWidth: true
      label: root.liveHdr ? "SDR brightness" : "Brightness"
      enabled: root.liveHdr || Brightness.available(root.name)
      from: root.liveHdr ? 0.5 : 1
      to: root.liveHdr ? 2 : 100
      step: root.liveHdr ? 0.05 : 1
      value: root.liveHdr ? root.monitor.sdrBrightness : Brightness.percentOf(root.name)
      onMoved: v => root.liveHdr ? Apply.setSdrBrightness(root.name, v) : Brightness.set(root.name, v)
    }
    Text {
      Layout.minimumWidth: Math.round(44 * Theme.unit)
      text: root.liveHdr ? M.trimNumber(root.monitor.sdrBrightness, 2) + "×"
          : Brightness.available(root.name) ? Brightness.percentOf(root.name) + "%" : "—"
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.body
    }
  }

  Text {
    visible: root.cfg.enabled
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    wrapMode: Text.Wrap
    text: {
      if (root.liveHdr)
        return "In HDR the panel ignores its backlight: the picture sets its own light. This sets how bright ordinary content looks; your brightness keys do the same. It's live, and saved with Save…."
      var backend = Brightness.backendOf(root.name)
      if (backend === "none") return /^(eDP|LVDS|DSI)-/.test(root.name) ? "No backlight control found." : "This monitor doesn't answer DDC/CI, so its brightness can't be set from here."
      if (!backend) return "Reading brightness…"
      return backend === "ddc" ? "Set over DDC/CI. Follows your brightness keys." : "Follows your brightness keys."
    }
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  ColumnLayout {
    readonly property var feat: Brightness.features[root.name] || null
    visible: root.cfg.enabled && Brightness.backendOf(root.name) === "ddc" && !!feat
    Layout.fillWidth: true
    spacing: Theme.space.lg
    Component.onCompleted: Brightness.loadFeatures(root.name)

    SettingRow {
      readonly property var vcp: parent.feat ? parent.feat.vcp["12"] : null
      visible: !!vcp && vcp.continuous
      label: "Contrast"
      Slider {
        Layout.fillWidth: true
        label: "Contrast"
        from: 0
        to: parent.vcp ? parent.vcp.max : 100
        step: 1
        value: parent.vcp ? parent.vcp.value : 0
        onMoved: v => Brightness.setVcp(root.name, "12", v)
      }
      Text {
        Layout.minimumWidth: Math.round(44 * Theme.unit)
        text: parent.vcp ? parent.vcp.value : ""
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }
    }

    SettingRow {
      readonly property var cap: parent.feat ? parent.feat.caps["60"] : null
      visible: !!cap && cap.values.length > 1
      label: "Input"
      Dropdown {
        Layout.fillWidth: true
        accessibleName: "Input source"
        options: parent.cap ? parent.cap.values : []
        value: parent.parent.feat && parent.parent.feat.vcp["60"] ? parent.parent.feat.vcp["60"].value : -1
        onPicked: v => Brightness.setVcp(root.name, "60", "0x" + Number(v).toString(16))
      }
    }

    SettingRow {
      readonly property var cap: parent.feat ? parent.feat.caps["14"] : null
      visible: !!cap && cap.values.length > 1
      label: "Preset"
      Dropdown {
        Layout.fillWidth: true
        accessibleName: "Monitor color preset"
        options: parent.cap ? parent.cap.values : []
        value: parent.parent.feat && parent.parent.feat.vcp["14"] ? parent.parent.feat.vcp["14"].value : -1
        onPicked: v => Brightness.setVcp(root.name, "14", "0x" + Number(v).toString(16))
      }
    }
  }

  SettingRow {
    visible: root.cfg.enabled
    label: "Resolution"
    changed: root.cfg.width !== root.base.width || root.cfg.height !== root.base.height
    Dropdown {
      Layout.fillWidth: true
      accessibleName: "Resolution"
      options: root.groups.map(function (g) {
        return { value: g.width + "x" + g.height, label: M.formatResolution(g.width, g.height) + "   " + M.aspectRatio(g.width, g.height) }
      })
      value: root.cfg.width + "x" + root.cfg.height
      onPicked: v => {
        var g = root.groups.find(function (x) { return x.width + "x" + x.height === v })
        if (!g) return
        var hz = g.refreshes.indexOf(root.cfg.refresh) >= 0 ? root.cfg.refresh : g.refreshes[0]
        Draft.setMode(root.name, g.width, g.height, hz)
      }
    }
  }

  SettingRow {
    visible: root.cfg.enabled
    label: "Refresh rate"
    changed: !D.sameField("refresh", root.cfg.refresh, root.base.refresh)
    Dropdown {
      Layout.fillWidth: true
      accessibleName: "Refresh rate"
      options: (root.group ? root.group.refreshes : [root.cfg.refresh]).map(function (r) {
        return { value: r, label: M.formatRefresh(r) }
      })
      value: root.cfg.refresh
      onPicked: v => Draft.setMode(root.name, root.cfg.width, root.cfg.height, Number(v))
    }
  }

  SettingRow {
    visible: root.cfg.enabled
    label: "Scale"
    changed: !D.sameField("scale", root.cfg.scale, root.base.scale)

    PButton {
      text: "−"
      implicitWidth: Theme.controlHeight
      enabled: S.step(root.cfg.width, root.cfg.height, root.cfg.scale, -1) !== null
      Accessible.name: "Smaller scale"
      onClicked: Draft.setScale(root.name, S.step(root.cfg.width, root.cfg.height, root.cfg.scale, -1))
    }

    Text {
      Layout.minimumWidth: Math.round(48 * Theme.unit)
      horizontalAlignment: Text.AlignHCenter
      text: M.formatScale(root.cfg.scale)
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.body
      font.bold: true
    }

    PButton {
      text: "+"
      implicitWidth: Theme.controlHeight
      enabled: S.step(root.cfg.width, root.cfg.height, root.cfg.scale, 1) !== null
      Accessible.name: "Larger scale"
      onClicked: Draft.setScale(root.name, S.step(root.cfg.width, root.cfg.height, root.cfg.scale, 1))
    }

    Text {
      Layout.fillWidth: true
      text: "= " + Math.round(root.logical.width) + "×" + Math.round(root.logical.height)
      elide: Text.ElideRight
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.caption
    }
  }

  Flow {
    visible: root.cfg.enabled
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    spacing: Theme.space.xs

    Repeater {
      model: S.presets(root.cfg.width, root.cfg.height)

      PButton {
        required property real modelData
        text: M.formatScale(modelData)
        implicitHeight: Math.round(Theme.controlHeight * 0.85)
        checked: D.sameField("scale", modelData, root.cfg.scale)
        onClicked: Draft.setScale(root.name, modelData)
      }
    }
  }

  SettingRow {
    visible: root.cfg.enabled
    label: "Rotation"
    changed: root.cfg.transform % 4 !== root.base.transform % 4
    Segmented {
      options: [{ value: 0, label: "0°" }, { value: 1, label: "90°" }, { value: 2, label: "180°" }, { value: 3, label: "270°" }]
      value: root.cfg.transform % 4
      onPicked: v => Draft.setTransform(root.name, v + (root.cfg.transform >= 4 ? 4 : 0))
    }
  }

  SettingRow {
    visible: root.cfg.enabled
    label: "Flipped"
    changed: (root.cfg.transform >= 4) !== (root.base.transform >= 4)
    Toggle {
      label: "Flipped"
      checked: root.cfg.transform >= 4
      onToggled: Draft.setTransform(root.name, (root.cfg.transform + 4) % 8)
    }
    Item { Layout.fillWidth: true }
  }

  SettingRow {
    visible: root.cfg.enabled && (root.targets.length > 0 || root.cfg.mirror !== "")
    label: "Mirror"
    changed: root.cfg.mirror !== root.base.mirror
    Dropdown {
      Layout.fillWidth: true
      accessibleName: "Mirror"
      options: [{ value: "", label: "Don't mirror" }].concat(root.targets.map(function (c) {
        return { value: c.name, label: "Mirror " + c.name }
      }))
      value: root.cfg.mirror
      onPicked: v => Draft.setMirror(root.name, v)
    }
  }

  SettingRow {
    visible: root.cfg.enabled
    label: "Position"
    changed: D.isPlaced(root.cfg) && (root.cfg.x !== root.base.x || root.cfg.y !== root.base.y)
    Text {
      Layout.fillWidth: true
      text: root.cfg.mirror ? "Follows " + root.cfg.mirror : root.cfg.x + ", " + root.cfg.y + "  · drag the tile"
      elide: Text.ElideRight
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.body
    }
  }

  SettingRow {
    label: "Save as"
    changed: Persist.savedMatch(root.name) !== "" && Persist.matchOf(root.name) !== Persist.savedMatch(root.name)
    Segmented {
      options: Persist.canMatchByMonitor(root.name)
               ? [{ value: "port", label: "Port " + root.name }, { value: "monitor", label: "This monitor" }]
               : [{ value: "port", label: "Port " + root.name }]
      value: Persist.matchOf(root.name)
      onPicked: v => Persist.setMatch(root.name, v)
    }
    Item { Layout.fillWidth: true }
  }

  Text {
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    wrapMode: Text.Wrap
    text: Persist.matchOf(root.name) === "monitor"
          ? "Saved settings follow this monitor to any port."
          : "Saved settings apply to whatever is plugged into " + root.name + "."
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  Text {
    visible: Apply.state !== "idle"
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: "Keep or revert the applied change to edit again."
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }
}
