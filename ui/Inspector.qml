import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"
import "../lib/monitor.js" as M

// The selected monitor: editable settings, or everything Hyprland reports.
Rectangle {
  id: root

  property var monitor: null
  property var monitors: []
  property string tab: "settings"

  color: Theme.alpha(Theme.foreground, 0.02)
  border.color: Theme.border
  radius: Theme.radius

  Text {
    anchors.centerIn: parent
    visible: !root.monitor
    text: "Select a display"
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.body
  }

  Flickable {
    id: flick
    visible: !!root.monitor
    anchors.fill: parent
    anchors.margins: Theme.space.xl
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    ColumnLayout {
      id: content
      width: flick.width - Theme.space.lg
      spacing: Theme.space.xl

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space.lg

        Rectangle {
          implicitWidth: Math.round(40 * Theme.unit)
          implicitHeight: implicitWidth
          radius: Theme.radius
          color: Theme.selected
          border.color: Theme.accent

          Text {
            anchors.centerIn: parent
            text: root.monitor ? Hypr.numberOf(root.monitor.name) : ""
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.heading
            font.bold: true
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Theme.space.xs

          Text {
            Layout.fillWidth: true
            text: root.monitor ? M.displayName(root.monitor) : ""
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.title
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: root.monitor
                  ? root.monitor.name + " · " + root.monitor.width + "×" + root.monitor.height + " @ " + M.formatRefresh(root.monitor.refreshRate)
                  : ""
            elide: Text.ElideRight
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
          }
        }
      }

      Flow {
        Layout.fillWidth: true
        spacing: Theme.space.sm
        visible: tagRepeater.count > 0

        Repeater {
          id: tagRepeater
          model: root.monitor ? M.tags(root.monitor) : []

          Rectangle {
            required property string modelData
            implicitWidth: tagLabel.implicitWidth + 2 * Theme.space.md
            implicitHeight: tagLabel.implicitHeight + 2 * Theme.space.xs
            radius: Theme.radius
            color: Theme.alpha(Theme.accent, 0.12)
            border.color: Theme.alpha(Theme.accent, 0.5)

            Text {
              id: tagLabel
              anchors.centerIn: parent
              text: modelData
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.caption
            }
          }
        }
      }

      Segmented {
        options: [
          { value: "settings", label: "Settings" },
          { value: "color", label: "Color" },
          { value: "details", label: "Details" },
          { value: "global", label: "Global" }
        ]
        value: root.tab
        onPicked: v => root.tab = v
      }

      Loader {
        Layout.fillWidth: true
        active: root.tab === "settings" && !!root.monitor
        visible: active
        sourceComponent: Component {
          SettingsPanel { monitor: root.monitor }
        }
      }

      Loader {
        Layout.fillWidth: true
        active: root.tab === "color" && !!root.monitor
        visible: active
        sourceComponent: Component {
          ColorPanel { monitor: root.monitor }
        }
      }

      Loader {
        Layout.fillWidth: true
        active: root.tab === "global"
        visible: active
        sourceComponent: Component {
          GlobalPanel {}
        }
      }

      Repeater {
        model: root.tab === "details" && root.monitor ? M.inspectorSections(root.monitor, root.monitors) : []

        InfoSection {
          required property var modelData
          Layout.fillWidth: true
          title: modelData.title
          rows: modelData.rows
        }
      }
    }
  }
}
