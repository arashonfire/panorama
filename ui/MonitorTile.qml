import QtQuick
import qs.services
import "../lib/monitor.js" as M

// One monitor on the layout canvas, drawn from its draft config. Drag gestures
// are reported in the parent's coordinates; the canvas turns them into moves.
Rectangle {
  id: root

  required property var cfg
  property var monitor: null
  property int number
  property bool selected
  property bool edited
  property bool dragging
  property bool draggable: true

  signal dragStarted(point p)
  signal dragMoved(point p)
  signal dragEnded()

  readonly property real unit: Math.min(width, height)

  radius: Theme.radius
  color: selected ? Theme.selected : mouse.containsMouse ? Theme.alpha(Theme.foreground, 0.1) : Theme.alpha(Theme.foreground, 0.05)
  border.width: selected || dragging ? 2 : 1
  border.color: selected || dragging ? Theme.accent : Theme.alpha(Theme.foreground, mouse.containsMouse ? 0.5 : 0.3)
  clip: true
  z: dragging ? 1 : 0

  Accessible.role: Accessible.Button
  Accessible.name: "Display " + number + ", " + cfg.name

  Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  Behavior on y { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  Text {
    anchors { left: parent.left; top: parent.top; margins: Theme.space.md }
    text: root.number
    color: root.selected ? Theme.accent : Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Math.max(Theme.font.body, Math.min(root.unit * 0.2, 40))
    font.bold: true
  }

  Rectangle {
    visible: !!root.monitor && root.monitor.focused
    anchors { right: parent.right; top: parent.top; margins: Theme.space.md }
    width: Math.round(8 * Theme.unit)
    height: width
    radius: width / 2
    color: Theme.accent
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - 2 * Theme.space.md
    spacing: Theme.space.xs
    visible: root.unit > 56

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.cfg.name
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Math.max(Theme.font.body, Math.min(root.unit * 0.12, 22))
      font.bold: true
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      visible: root.unit > 90
      text: root.cfg.width + "×" + root.cfg.height + " @ " + M.formatRefresh(root.cfg.refresh)
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Math.max(Theme.font.caption, Math.min(root.unit * 0.075, 14))
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      visible: root.unit > 90
      readonly property var rotations: ["", "90°", "180°", "270°", "flipped", "flipped 90°", "flipped 180°", "flipped 270°"]
      text: "scale " + M.formatScale(root.cfg.scale) + (root.cfg.transform ? " · " + rotations[root.cfg.transform] : "")
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Math.max(Theme.font.caption, Math.min(root.unit * 0.075, 14))
    }
  }

  Text {
    visible: root.edited && root.unit > 70
    anchors { left: parent.left; bottom: parent.bottom; margins: Theme.space.md }
    text: "edited"
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.dragging ? Qt.ClosedHandCursor : root.draggable ? Qt.OpenHandCursor : Qt.PointingHandCursor
    onPressed: ev => root.dragStarted(mapToItem(root.parent, ev.x, ev.y))
    onPositionChanged: ev => {
      if (pressed) root.dragMoved(mapToItem(root.parent, ev.x, ev.y))
    }
    onReleased: root.dragEnded()
  }
}
