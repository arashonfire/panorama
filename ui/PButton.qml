import QtQuick
import qs.services

// Themed push button, styled after Omarchy's control tokens. `checked` gives
// it the persistent selected look (used by chips).
Rectangle {
  id: root

  property string text
  property bool checked: false
  signal clicked()

  implicitWidth: label.implicitWidth + 2 * Theme.space.lg
  implicitHeight: Theme.controlHeight
  radius: Theme.radius
  color: mouse.pressed ? Theme.alpha(Theme.foreground, 0.2)
       : checked ? Theme.selected
       : mouse.containsMouse || activeFocus ? Theme.hover
       : Theme.alpha(Theme.foreground, 0.04)
  border.width: 1
  border.color: checked || activeFocus ? Theme.accent : Theme.alpha(Theme.foreground, mouse.containsMouse ? 0.4 : 0.25)

  opacity: enabled ? 1 : 0.4
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: text
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.checked ? Theme.accent : Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.body
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
