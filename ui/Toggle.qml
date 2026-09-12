import QtQuick
import "../services"

// On/off switch. The owner holds the value: bind `checked`, act on `toggled`.
Item {
  id: root

  property bool checked: false
  property string label
  signal toggled()

  implicitWidth: Math.round(40 * Theme.unit)
  implicitHeight: Math.round(22 * Theme.unit)
  opacity: enabled ? 1 : 0.4

  activeFocusOnTab: true
  Accessible.role: Accessible.CheckBox
  Accessible.checkable: true
  Accessible.checked: checked
  Accessible.name: label
  Keys.onSpacePressed: toggled()
  Keys.onReturnPressed: toggled()

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius > 0 ? height / 2 : 0
    color: root.checked ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.foreground, 0.06)
    border.width: 1
    border.color: root.activeFocus || root.checked ? Theme.accent : Theme.alpha(Theme.foreground, mouse.containsMouse ? 0.5 : 0.3)

    Rectangle {
      width: parent.height - 6
      height: width
      y: 3
      x: root.checked ? parent.width - width - 3 : 3
      radius: Theme.radius > 0 ? width / 2 : 0
      color: root.checked ? Theme.accent : Theme.muted
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
