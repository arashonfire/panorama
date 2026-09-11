import QtQuick
import QtQuick.Layouts
import qs.services

// The keyboard shortcuts, shown with ? or F1.
Item {
  id: root

  property bool open: false
  signal dismissed()

  readonly property var keys: [
    ["← → ↑ ↓", "Select the previous / next display"],
    ["Alt + arrows", "Move the selected display (Shift + Alt: fine steps)"],
    ["Tab / Shift + Tab", "Move between controls"],
    ["Space / Enter", "Press a button, open a list, flip a switch"],
    ["Ctrl + 1 … 4", "Settings, Color, Details, Global tab"],
    ["Ctrl + Enter", "Apply"],
    ["Enter / Esc", "Keep / revert while a change waits for confirmation"],
    ["Ctrl + S", "Save…"],
    ["Ctrl + P", "Profiles…"],
    ["I", "Identify displays"],
    ["Ctrl + R", "Refresh"],
    ["? / F1", "This list"],
    ["Esc", "Close a dialog, or Panorama"]
  ]

  visible: open
  onOpenChanged: if (open) card.forceActiveFocus()

  Rectangle {
    anchors.fill: parent
    color: Theme.alpha(Theme.background, 0.75)
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.dismissed()
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - 2 * Theme.space.xl, column.implicitWidth + 2 * Theme.space.xl)
    height: column.implicitHeight + 2 * Theme.space.xl
    radius: Theme.radius
    color: Theme.background
    border.color: Theme.accent
    border.width: 2

    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape || event.key === Qt.Key_Question || event.key === Qt.Key_F1) {
        root.dismissed()
        event.accepted = true
      }
    }

    Accessible.role: Accessible.Dialog
    Accessible.name: "Keyboard shortcuts"

    ColumnLayout {
      id: column
      anchors { left: parent.left; top: parent.top; margins: Theme.space.xl }
      spacing: Theme.space.md

      Text {
        text: "Keyboard shortcuts"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.title
        font.bold: true
      }

      GridLayout {
        columns: 2
        columnSpacing: Theme.space.xl
        rowSpacing: Theme.space.sm

        Repeater {
          model: root.keys.length * 2

          Text {
            required property int index
            readonly property var row: root.keys[Math.floor(index / 2)]
            text: row[index % 2]
            color: index % 2 === 0 ? Theme.accent : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
          }
        }
      }
    }
  }
}
