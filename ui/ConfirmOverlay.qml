import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// "Keep these display settings?" in the middle of every screen while an
// applied change waits for confirmation, so it's reachable even if the main
// window's screen went dark or moved. Without anchors, layer-shell centres it.
PanelWindow {
  id: root

  required property var modelData

  screen: modelData
  visible: Apply.state === "confirming"
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "panorama-confirm"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight

  Rectangle {
    id: card
    implicitWidth: Math.max(Math.round(440 * Theme.unit), column.implicitWidth + 2 * Theme.space.xl)
    implicitHeight: column.implicitHeight + 2 * Theme.space.xl
    radius: Theme.radius
    color: Theme.alpha(Theme.background, 0.97)
    border.color: Theme.accent
    border.width: 2
    focus: true

    Keys.onReturnPressed: Apply.keep()
    Keys.onEnterPressed: Apply.keep()
    Keys.onEscapePressed: Apply.revert()

    ColumnLayout {
      id: column
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space.xl }
      spacing: Theme.space.md

      Text {
        text: "Keep these display settings?"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.title
        font.bold: true
      }

      Text {
        text: "Reverting in " + Apply.secondsLeft + " s"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 3
        color: Theme.border
        Rectangle {
          width: parent.width * Apply.secondsLeft / Apply.timeout
          height: parent.height
          color: Theme.accent
          Behavior on width { NumberAnimation { duration: 1000 } }
        }
      }

      Repeater {
        model: Apply.issues
        Text {
          required property string modelData
          Layout.fillWidth: true
          Layout.maximumWidth: Math.round(520 * Theme.unit)
          wrapMode: Text.Wrap
          text: "⚠ " + modelData
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.caption
        }
      }

      RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: Theme.space.md

        PButton {
          text: "Revert"
          onClicked: Apply.revert()
        }

        PButton {
          text: "Keep changes"
          checked: true
          onClicked: Apply.keep()
        }
      }
    }
  }
}
