import QtQuick
import QtQuick.Layouts
import "../services"

// A titled block of label/value rows. Values are selectable so serials and
// descriptions can be copied.
ColumnLayout {
  id: root

  property string title
  property var rows: []

  spacing: Theme.space.sm

  Text {
    text: root.title.toUpperCase()
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
    font.letterSpacing: 1
    font.bold: true
    Accessible.role: Accessible.Heading
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: Theme.border
  }

  Repeater {
    model: root.rows

    RowLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: Theme.space.lg

      Text {
        Layout.preferredWidth: Math.round(120 * Theme.unit)
        Layout.alignment: Qt.AlignTop
        text: modelData.label
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }

      TextEdit {
        Layout.fillWidth: true
        text: modelData.value
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        color: Theme.foreground
        selectionColor: Theme.alpha(Theme.accent, 0.35)
        selectedTextColor: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
        Accessible.name: modelData.label
      }
    }
  }
}
