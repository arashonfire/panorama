import QtQuick
import QtQuick.Layouts
import "../services"

// Label + controls. An accent bar marks a setting that differs from the live state.
RowLayout {
  id: root

  property string label
  property bool changed: false
  property int labelWidth: Math.round(96 * Theme.unit)
  default property alias content: slot.data

  Layout.fillWidth: true
  spacing: Theme.space.md

  Rectangle {
    implicitWidth: 3
    implicitHeight: Math.round(Theme.controlHeight * 0.7)
    color: Theme.accent
    opacity: root.changed ? 1 : 0
  }

  Text {
    Layout.preferredWidth: root.labelWidth
    wrapMode: Text.Wrap
    text: root.label
    color: root.changed ? Theme.foreground : Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.body
  }

  RowLayout {
    id: slot
    Layout.fillWidth: true
    spacing: Theme.space.sm
  }
}
