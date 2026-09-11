import QtQuick
import qs.services

// Single-line text input. Commits on Enter or when focus leaves; the owner
// holds the text.
Rectangle {
  id: root

  property string text
  property string placeholder
  property string label
  signal committed(string text)

  implicitWidth: Math.round(220 * Theme.unit)
  implicitHeight: Theme.controlHeight
  radius: Theme.radius
  color: Theme.alpha(Theme.foreground, 0.04)
  border.width: 1
  border.color: input.activeFocus ? Theme.accent : Theme.alpha(Theme.foreground, 0.25)
  opacity: enabled ? 1 : 0.4

  TextInput {
    id: input
    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Theme.space.md }
    clip: true
    selectByMouse: true
    color: Theme.foreground
    selectionColor: Theme.alpha(Theme.accent, 0.35)
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.body
    Accessible.name: root.label
    onEditingFinished: if (text !== root.text) root.committed(text)

    Text {
      anchors.fill: parent
      visible: !input.text.length && !input.activeFocus
      text: root.placeholder
      elide: Text.ElideRight
      color: Theme.muted
      font: input.font
    }
  }

  // Follow the owner's text unless the user is typing.
  Binding {
    target: input
    property: "text"
    value: root.text
    when: !input.activeFocus
  }
}
