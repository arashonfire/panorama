import QtQuick
import "../services"

// Number input with a unit. Commits on Enter or when focus leaves; the owner
// holds the value.
Rectangle {
  id: root

  property real value: 0
  property real from: 0
  property real to: 100000
  property int decimals: 0
  property string suffix
  property string label
  signal committed(real value)

  function format(v) {
    return String(Number(Number(v).toFixed(decimals)))
  }

  implicitWidth: Math.round(110 * Theme.unit)
  implicitHeight: Theme.controlHeight
  radius: Theme.radius
  color: Theme.alpha(Theme.foreground, 0.04)
  border.width: 1
  border.color: input.activeFocus ? Theme.accent : Theme.alpha(Theme.foreground, 0.25)
  opacity: enabled ? 1 : 0.4

  TextInput {
    id: input
    anchors { left: parent.left; right: unit.left; verticalCenter: parent.verticalCenter; leftMargin: Theme.space.md; rightMargin: Theme.space.sm }
    clip: true
    activeFocusOnTab: true
    selectByMouse: true
    color: Theme.foreground
    selectionColor: Theme.alpha(Theme.accent, 0.35)
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.body
    validator: DoubleValidator { bottom: root.from; top: root.to; decimals: root.decimals; notation: DoubleValidator.StandardNotation }
    Accessible.name: root.label
    onEditingFinished: {
      var v = Number(text)
      if (text.length && isFinite(v)) root.committed(Math.max(root.from, Math.min(root.to, v)))
      text = root.format(root.value)
    }
  }

  // Follow the value unless the user is typing.
  Binding {
    target: input
    property: "text"
    value: root.format(root.value)
    when: !input.activeFocus
  }

  Text {
    id: unit
    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Theme.space.md }
    text: root.suffix
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }
}
