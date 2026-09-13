import QtQuick
import QtQuick.Layouts
import "../services"
import "../lib/monitor.js" as M
import "../lib/draft.js" as D
import "../lib/edid.js" as E
import "../lib/globals.js" as G

// Color, HDR and VRR for one monitor. The controls edit what the monitor asks
// for; where Hyprland can end up doing something else, that's shown too.
ColumnLayout {
  id: root

  required property var monitor
  readonly property string name: monitor.name
  readonly property var cfg: Draft.config(name) || D.fromLive(monitor, Hypr.monitors, null)
  readonly property var base: Draft.baseOf(name) || cfg
  readonly property var edid: Edid.byName[name] || null
  readonly property bool hdr: M.isHdr(cfg.cm)
  readonly property string effectiveCm: monitor.colorManagementPreset || "srgb"
  // HDR and 10-bit controls for panels that can't do them are hidden; "Show
  // anyway" is for an EDID that undersells the panel.
  property bool showAll: false
  readonly property var support: E.supports(edid)
  readonly property var offers: showAll ? { hdr: true, tenBit: true }
    : D.colorOffers(support, [cfg, base, { cm: effectiveCm, bitdepth: M.pixelFormat(monitor.currentFormat).bits }])
  readonly property var hidden: [offers.hdr ? "" : "HDR", offers.tenBit ? "" : "10-bit"].filter(function (s) { return s })
  readonly property bool overridesLuminance: cfg.min_luminance >= 0 || cfg.max_luminance >= 0 || cfg.max_avg_luminance >= 0
  readonly property int labelIndent: 3 + Math.round(96 * Theme.unit) + 2 * Theme.space.md
  readonly property var tristate: [{ value: 0, label: "Auto" }, { value: 1, label: "On" }, { value: -1, label: "Off" }]
  readonly property var eotfLabels: ({ "default": "Default", "auto": "Auto", "srgb": "sRGB", "gamma22": "Gamma 2.2", "gamma22force": "Gamma 2.2 (forced)" })

  function changed(key) { return !D.sameField(key, cfg[key], base[key]) }
  function set(fields) { Draft.set(name, fields) }

  // Switching to HDR also turns on 10-bit, lifts SDR white from Hyprland's
  // dim 80-nit default to the 203-nit reference white (BT.2408), and, when the
  // panel advertises HDR10, forces HDR and wide color support, which Hyprland
  // misreads on some panels.
  function pickPreset(v) {
    if (!M.isHdr(v) || hdr) {
      set({ cm: v })
      return
    }
    var f = { cm: v, bitdepth: 10 }
    if (cfg.sdr_max_luminance === 80) f.sdr_max_luminance = 203
    if (edid && edid.hdr.pq) {
      if (cfg.supports_hdr === 0) f.supports_hdr = 1
      if (cfg.supports_wide_color === 0) f.supports_wide_color = 1
    }
    set(f)
  }

  // Hyprland's supportsHDR() is false unless wide color is supported too, so
  // forcing HDR also forces wide color (unless that was explicitly turned off).
  function setHdrSupport(v) {
    set(v === 1 && cfg.supports_wide_color === 0 ? { supports_hdr: 1, supports_wide_color: 1 } : { supports_hdr: v })
  }

  spacing: Theme.space.lg
  enabled: Apply.state === "idle"

  Text {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: root.edid
          ? "Panel advertises: " + (E.summary(root.edid) || "no HDR, wide color or VRR")
          : Edid.available ? "No EDID for this output." : "Install edid-decode to see what the panel supports."
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  RowLayout {
    visible: root.hidden.length > 0
    Layout.fillWidth: true
    spacing: Theme.space.md

    Text {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: root.hidden.join(" and ") + " settings are hidden: the panel doesn't advertise "
            + [root.offers.hdr ? "" : "HDR10", root.offers.tenBit ? "" : "10-bit color"].filter(function (s) { return s }).join(" or ") + "."
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.caption
    }

    PButton {
      text: "Show anyway"
      onClicked: root.showAll = true
    }
  }

  SettingRow {
    label: "Color"
    changed: root.changed("cm")
    Dropdown {
      Layout.fillWidth: true
      accessibleName: "Color preset"
      options: D.CM_PRESETS.filter(function (p) { return root.offers.hdr || !M.isHdr(p) })
                           .map(function (p) { return { value: p, label: M.colorPresetLabel(p) } })
      value: root.cfg.cm
      onPicked: v => root.pickPreset(v)
    }
  }

  RowLayout {
    id: fallback
    // Hyprland decided the panel can't do HDR. Not when support is forced on:
    // then supportsHDR() is true regardless, and sRGB on screen means the
    // rule hasn't landed, or something else is in the way.
    readonly property bool fellBack: M.isHdr(root.cfg.cm) && !M.isHdr(root.effectiveCm)
                                     && !(root.cfg.supports_hdr === 1 && root.cfg.supports_wide_color === 1)
    visible: !Draft.isChanged(root.name) && !root.cfg.icc && root.cfg.cm !== "auto" && root.cfg.cm !== root.effectiveCm
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    spacing: Theme.space.md

    Text {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: "Hyprland is showing " + M.colorPresetLabel(root.effectiveCm)
            + (fallback.fellBack ? ": it doesn't think this panel supports HDR."
                                   + (root.edid && root.edid.hdr.pq ? " The panel does advertise HDR10." : "")
                                 : ".")
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.caption
    }

    PButton {
      visible: fallback.fellBack && root.cfg.supports_hdr !== 1
      text: "Force HDR"
      onClicked: root.setHdrSupport(1)
    }
  }

  // Shown while the monitor is in HDR: the one situation where the panel can
  // silently fall out of it (after a suspend) with Hyprland none the wiser.
  RowLayout {
    visible: M.isHdr(root.effectiveCm) && !root.cfg.icc && Apply.state === "idle"
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    spacing: Theme.space.md

    Text {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: "Washed out and greyish, say after a sleep? The panel may have dropped out of HDR without Hyprland noticing."
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.caption
    }

    PButton {
      text: Apply.resending === root.name ? "Re-sending…" : "Re-send HDR"
      enabled: !Apply.resending
      onClicked: Apply.resendHdr(root.name)
    }
  }

  SettingRow {
    visible: root.offers.tenBit
    label: "10-bit"
    changed: root.changed("bitdepth")
    Toggle {
      label: "10-bit"
      checked: root.cfg.bitdepth === 10
      onToggled: root.set({ bitdepth: root.cfg.bitdepth === 10 ? 8 : 10 })
    }
    Text {
      Layout.fillWidth: true
      text: "output is " + (M.pixelFormat(root.monitor.currentFormat).name || "?")
      elide: Text.ElideRight
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.caption
    }
  }

  SettingRow {
    visible: root.offers.hdr
    label: "HDR support"
    changed: root.changed("supports_hdr")
    Segmented {
      options: root.tristate
      value: root.cfg.supports_hdr
      onPicked: v => root.setHdrSupport(v)
    }
  }

  SettingRow {
    label: "Wide color"
    changed: root.changed("supports_wide_color")
    Segmented {
      options: root.tristate
      value: root.cfg.supports_wide_color
      onPicked: v => root.set({ supports_wide_color: v })
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    wrapMode: Text.Wrap
    text: "Auto trusts Hyprland's reading of the EDID; On forces support for panels it misreads."
          + (root.offers.hdr ? " HDR also needs wide color, so forcing HDR forces wide color too." : "")
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  ColumnLayout {
    visible: root.hdr
    Layout.fillWidth: true
    spacing: Theme.space.lg

    SectionHeader { title: "SDR content in HDR" }

    SettingRow {
      label: "Brightness"
      changed: root.changed("sdrbrightness")
      Slider {
        Layout.fillWidth: true
        label: "SDR brightness"
        from: 0.5
        to: 2
        step: 0.05
        value: root.cfg.sdrbrightness
        onMoved: v => root.set({ sdrbrightness: v })
      }
      Text {
        Layout.minimumWidth: Math.round(44 * Theme.unit)
        text: M.trimNumber(root.cfg.sdrbrightness, 2) + "×"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }
    }

    SettingRow {
      label: "Saturation"
      changed: root.changed("sdrsaturation")
      Slider {
        Layout.fillWidth: true
        label: "SDR saturation"
        from: 0.5
        to: 1.5
        step: 0.05
        value: root.cfg.sdrsaturation
        onMoved: v => root.set({ sdrsaturation: v })
      }
      Text {
        Layout.minimumWidth: Math.round(44 * Theme.unit)
        text: M.trimNumber(root.cfg.sdrsaturation, 2) + "×"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }
    }

    SettingRow {
      label: "White level"
      changed: root.changed("sdr_max_luminance")
      NumberField {
        label: "SDR white level"
        value: root.cfg.sdr_max_luminance
        from: 40
        to: 2000
        suffix: "nits"
        onCommitted: v => root.set({ sdr_max_luminance: Math.round(v) })
      }
      Item { Layout.fillWidth: true }
    }

    SettingRow {
      label: "Black level"
      changed: root.changed("sdr_min_luminance")
      NumberField {
        label: "SDR black level"
        value: root.cfg.sdr_min_luminance
        from: 0
        to: 10
        decimals: 3
        suffix: "nits"
        onCommitted: v => root.set({ sdr_min_luminance: v })
      }
      Item { Layout.fillWidth: true }
    }

    SettingRow {
      label: "Transfer"
      changed: root.changed("sdr_eotf")
      Dropdown {
        Layout.fillWidth: true
        accessibleName: "SDR transfer function"
        options: D.SDR_EOTFS.map(function (e) { return { value: e, label: root.eotfLabels[e] } })
        value: root.cfg.sdr_eotf
        onPicked: v => root.set({ sdr_eotf: v })
      }
    }

    SectionHeader { title: "Panel luminance" }

    SettingRow {
      label: "Override"
      changed: root.changed("max_luminance") || root.changed("max_avg_luminance") || root.changed("min_luminance")
      Toggle {
        label: "Override the panel's luminance"
        checked: root.overridesLuminance
        onToggled: {
          if (root.overridesLuminance) {
            root.set({ min_luminance: -1, max_luminance: -1, max_avg_luminance: -1 })
            return
          }
          var fromEdid = E.luminanceOverrides(root.edid)
          root.set(fromEdid && fromEdid.max_luminance > 0 ? fromEdid : { min_luminance: 0.005, max_luminance: 1000, max_avg_luminance: 400 })
        }
      }
      Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.overridesLuminance ? "starts from the panel's own numbers" : "Hyprland uses what the EDID says"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.caption
      }
    }

    SettingRow {
      visible: root.overridesLuminance
      label: "Peak"
      changed: root.changed("max_luminance")
      NumberField {
        label: "Peak luminance"
        value: root.cfg.max_luminance
        from: 50
        to: 10000
        suffix: "nits"
        onCommitted: v => root.set({ max_luminance: Math.round(v) })
      }
      Item { Layout.fillWidth: true }
    }

    SettingRow {
      visible: root.overridesLuminance
      label: "Average"
      changed: root.changed("max_avg_luminance")
      NumberField {
        label: "Average luminance"
        value: root.cfg.max_avg_luminance
        from: 50
        to: 10000
        suffix: "nits"
        onCommitted: v => root.set({ max_avg_luminance: Math.round(v) })
      }
      Item { Layout.fillWidth: true }
    }

    SettingRow {
      visible: root.overridesLuminance
      label: "Minimum"
      changed: root.changed("min_luminance")
      NumberField {
        label: "Minimum luminance"
        value: root.cfg.min_luminance
        from: 0
        to: 10
        decimals: 3
        suffix: "nits"
        onCommitted: v => root.set({ min_luminance: v })
      }
      Item { Layout.fillWidth: true }
    }
  }

  SectionHeader { title: "Calibration" }

  SettingRow {
    label: "ICC profile"
    changed: root.changed("icc")
    TextField {
      Layout.fillWidth: true
      label: "ICC profile path"
      placeholder: "/path/to/profile.icc"
      text: root.cfg.icc
      onCommitted: t => root.set({ icc: t.trim() })
    }
    PButton {
      visible: root.cfg.icc.length > 0
      text: "Clear"
      onClicked: root.set({ icc: "" })
    }
  }

  Text {
    visible: root.cfg.icc.length > 0 || root.base.icc.length > 0
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    wrapMode: Text.Wrap
    text: root.base.icc && !root.cfg.icc
          ? "Removing a profile takes effect after saving."
          : "An ICC profile replaces the color preset."
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  SectionHeader { title: "Variable refresh rate" }

  SettingRow {
    label: "VRR"
    changed: root.changed("vrr")
    Dropdown {
      Layout.fillWidth: true
      accessibleName: "Variable refresh rate"
      options: [-1, 0, 1, 2, 3].map(function (v) {
        return { value: v, label: v === -1 ? "Use global (" + G.label("misc:vrr", Draft.globals["misc:vrr"]) + ")" : D.VRR_LABELS[v] }
      })
      value: root.cfg.vrr
      onPicked: v => root.set({ vrr: Number(v) })
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.leftMargin: root.labelIndent
    wrapMode: Text.Wrap
    text: (root.edid && root.edid.vrr ? "Panel range " + root.edid.vrr.min + "–" + root.edid.vrr.max + " Hz. " : "")
          + "Hyprland reports VRR as " + (root.monitor.vrr ? "active" : "inactive") + "."
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
