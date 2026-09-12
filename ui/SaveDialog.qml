import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

// Shows exactly what saving will write before anything touches the file.
Item {
  id: root

  property bool open: false
  signal dismissed()

  visible: open
  onOpenChanged: if (open) card.forceActiveFocus()

  function confirm() {
    Persist.save()
    dismissed()
  }

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
    width: Math.min(parent.width - 2 * Theme.space.xl, Math.round(860 * Theme.unit))
    height: Math.min(parent.height - 2 * Theme.space.xl, column.implicitHeight + 2 * Theme.space.xl)
    radius: Theme.radius
    color: Theme.background
    border.color: Theme.accent
    border.width: 2

    Keys.onEscapePressed: root.dismissed()
    Keys.onReturnPressed: if (Persist.canSave) root.confirm()
    Keys.onEnterPressed: if (Persist.canSave) root.confirm()

    MouseArea { anchors.fill: parent } // keep clicks off the scrim

    ColumnLayout {
      id: column
      anchors { fill: parent; margins: Theme.space.xl }
      spacing: Theme.space.md

      Text {
        text: "Save to " + Persist.displayPath
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.title
        font.bold: true
      }

      Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Persist.parsed.hasBlock
              ? "Panorama will replace its section with the lines below. The rest of the file stays exactly as it is."
              : "Panorama will add this section at the end of the file. The rest of the file stays exactly as it is."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }

      // A config that never loads the file would take the save silently.
      Rectangle {
        visible: !Persist.configLoads
        Layout.fillWidth: true
        implicitHeight: warning.implicitHeight + 2 * Theme.space.md
        radius: Theme.radius
        color: Theme.alpha(Theme.urgent, 0.1)
        border.color: Theme.urgent

        ColumnLayout {
          id: warning
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space.md }
          spacing: Theme.space.sm

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Persist.configIssue
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
          }

          PButton {
            visible: Persist.configState === "missing"
            text: "Add require(\"" + Persist.module + "\") to hyprland.lua"
            onClicked: Persist.addRequire()
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(code.implicitHeight + 2 * Theme.space.md, Math.round(300 * Theme.unit))
        Layout.minimumHeight: Math.round(80 * Theme.unit)
        radius: Theme.radius
        color: Theme.alpha(Theme.foreground, 0.04)
        border.color: Theme.border

        Flickable {
          id: flick
          anchors { fill: parent; margins: Theme.space.md }
          contentWidth: code.implicitWidth
          contentHeight: code.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

          TextEdit {
            id: code
            text: Persist.sectionLines.join("\n")
            readOnly: true
            selectByMouse: true
            color: Theme.foreground
            selectionColor: Theme.alpha(Theme.accent, 0.35)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
          }
        }
      }

      Text {
        visible: !!Persist.activeProfile
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Persist.activeProfile ? "This also updates the profile “" + Persist.activeProfile.name + "”, which matches the connected monitors." : ""
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.caption
      }

      Repeater {
        model: Persist.conflicts

        Text {
          required property var modelData
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          text: modelData.wins
                ? "⚠ Line " + modelData.line + " sets " + modelData.output + " after Panorama's section, so it will override what you save here."
                : "Line " + modelData.line + " (" + (modelData.output || "all monitors") + ") comes earlier and is overridden by Panorama's section."
          color: modelData.wins ? Theme.urgent : Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.caption
        }
      }

      Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "The current file is backed up first (panorama --revert restores it). Hyprland then reloads its config; if that reports new errors, the backup is put back automatically."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.caption
      }

      RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: Theme.space.md

        PButton {
          text: "Cancel"
          onClicked: root.dismissed()
        }

        PButton {
          text: "Save"
          checked: true
          enabled: Persist.canSave
          onClicked: root.confirm()
        }
      }
    }
  }
}
