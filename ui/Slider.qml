import QtQuick
import "../services"

// Horizontal slider snapping to `step`. The owner holds the value: bind
// `value` and act on `moved` (fires continuously while dragging).
Item {
  id: root

  property real from: 0
  property real to: 1
  property real step: 0.05
  property real value: 0
  property string label
  signal moved(real value)

  readonly property real fraction: Math.max(0, Math.min(1, (value - from) / (to - from)))

  function snap(v) {
    var s = Math.round((v - from) / step) * step + from
    return Number(Math.max(from, Math.min(to, s)).toFixed(4))
  }

  function moveTo(x) {
    var v = snap(from + (x / width) * (to - from))
    if (v !== value) moved(v)
  }

  implicitWidth: Math.round(180 * Theme.unit)
  implicitHeight: Theme.controlHeight
  opacity: enabled ? 1 : 0.4

  activeFocusOnTab: true
  Accessible.role: Accessible.Slider
  Accessible.name: label
  Keys.onLeftPressed: moved(snap(value - step))
  Keys.onRightPressed: moved(snap(value + step))

  Rectangle {
    id: track
    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
    height: 4
    radius: 2
    color: Theme.alpha(Theme.foreground, 0.15)

    Rectangle {
      width: parent.width * root.fraction
      height: parent.height
      radius: parent.radius
      color: Theme.accent
    }
  }

  Rectangle {
    width: Math.round(14 * Theme.unit)
    height: width
    radius: Theme.radius > 0 ? width / 2 : 2
    x: root.fraction * (root.width - width)
    anchors.verticalCenter: parent.verticalCenter
    color: Theme.background
    border.width: 2
    border.color: root.activeFocus || mouse.pressed ? Theme.foreground : Theme.accent
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onPressed: ev => root.moveTo(ev.x)
    onPositionChanged: ev => { if (pressed) root.moveTo(ev.x) }
  }
}
