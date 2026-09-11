import QtQuick
import QtQuick.Layouts
import qs.services
import "../lib/globals.js" as G

// Hyprland's global display options. They go through the same apply →
// confirm flow as monitor settings, and are saved in Panorama's section.
ColumnLayout {
  id: root

  readonly property int labelWidth: Math.round(150 * Theme.unit)

  spacing: Theme.space.lg
  enabled: Apply.state === "idle"

  Text {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: "These apply to every display. A monitor's own VRR setting (Color tab) wins over the global one."
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  Repeater {
    model: ["Sync", "Rendering", "Color"]

    ColumnLayout {
      id: group
      required property string modelData
      Layout.fillWidth: true
      spacing: Theme.space.md

      SectionHeader { title: group.modelData }

      Repeater {
        model: G.OPTIONS.filter(function (o) { return o.group === group.modelData })

        ColumnLayout {
          id: row
          required property var modelData
          readonly property var value: Draft.globals[modelData.key]
          Layout.fillWidth: true
          spacing: Theme.space.xs

          SettingRow {
            label: row.modelData.label
            labelWidth: root.labelWidth
            changed: Draft.globalChanges[row.modelData.key] !== undefined

            Toggle {
              visible: row.modelData.type === "bool"
              label: row.modelData.label
              checked: !!row.value
              onToggled: Draft.setGlobal(row.modelData.key, !row.value)
            }

            Dropdown {
              visible: row.modelData.type !== "bool"
              Layout.fillWidth: true
              accessibleName: row.modelData.label
              options: row.modelData.choices || []
              value: row.value
              onPicked: v => Draft.setGlobal(row.modelData.key, v)
            }

            Item {
              visible: row.modelData.type === "bool"
              Layout.fillWidth: true
            }
          }

          Text {
            Layout.fillWidth: true
            Layout.leftMargin: 3 + root.labelWidth + 2 * Theme.space.md
            wrapMode: Text.Wrap
            text: row.modelData.help
            color: row.modelData.restart && Draft.globalChanges[row.modelData.key] !== undefined ? Theme.accent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
          }
        }
      }
    }
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
