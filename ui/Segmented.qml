import QtQuick
import "../services"

// A row of mutually exclusive buttons. `options` is [{ value, label }].
Row {
  id: root

  property var options: []
  property var value
  signal picked(var value)

  spacing: Theme.space.xs

  Repeater {
    model: root.options

    PButton {
      required property var modelData
      text: modelData.label
      checked: modelData.value === root.value
      Accessible.role: Accessible.RadioButton
      Accessible.checked: checked
      onClicked: root.picked(modelData.value)
    }
  }
}
