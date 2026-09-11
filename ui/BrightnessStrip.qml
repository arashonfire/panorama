import QtQuick
import QtQuick.Layouts
import qs.services

// Every adjustable monitor's brightness side by side, for multi-monitor
// setups. Changes apply at once, like the brightness keys.
Rectangle {
  id: root

  readonly property var names: Hypr.monitors.filter(function (m) { return !m.disabled && Brightness.available(m.name) })
                                            .map(function (m) { return m.name })

  visible: names.length > 1
  implicitHeight: row.implicitHeight + 2 * Theme.space.md
  radius: Theme.radius
  color: Theme.alpha(Theme.foreground, 0.02)
  border.color: Theme.border

  RowLayout {
    id: row
    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Theme.space.md }
    spacing: Theme.space.xl

    Text {
      text: "Brightness"
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.caption
    }

    Repeater {
      model: root.names

      RowLayout {
        required property string modelData
        Layout.fillWidth: true
        spacing: Theme.space.sm

        Text {
          text: Hypr.numberOf(modelData) + "  " + modelData
          color: Theme.foreground
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.caption
        }

        Slider {
          Layout.fillWidth: true
          Layout.minimumWidth: Math.round(80 * Theme.unit)
          label: "Brightness of " + modelData
          from: 1
          to: 100
          step: 1
          value: Brightness.percentOf(modelData)
          onMoved: v => Brightness.set(modelData, v)
        }

        Text {
          Layout.minimumWidth: Math.round(36 * Theme.unit)
          text: Brightness.percentOf(modelData) + "%"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.caption
        }
      }
    }
  }
}
