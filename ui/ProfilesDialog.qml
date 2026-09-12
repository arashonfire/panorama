import QtQuick
// Qualified, so TextField below is Panorama's own (ui/TextField.qml), not Qt's.
import QtQuick.Controls as QQC
import QtQuick.Layouts
import "../services"
import "../lib/profiles.js" as P
import "../lib/monitor.js" as M

// Profiles: one layout per set of connected monitors, switched automatically
// by Hyprland when monitors come and go. Edits here are saved with Save….
Item {
  id: root

  property bool open: false
  signal dismissed()

  visible: open
  onOpenChanged: if (open) card.forceActiveFocus()

  function monitorLabel(entry) {
    var mon = null
    Hypr.monitors.forEach(function (m) { if (m.name === entry.port) mon = m })
    if (entry.match.indexOf("desc:") === 0) return entry.match.slice(5) + "  (any port)"
    return entry.port + (mon ? "  " + M.displayName(mon) : "")
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
    width: Math.min(parent.width - 2 * Theme.space.xl, Math.round(760 * Theme.unit))
    height: Math.min(parent.height - 2 * Theme.space.xl, column.implicitHeight + 2 * Theme.space.xl)
    radius: Theme.radius
    color: Theme.background
    border.color: Theme.accent
    border.width: 2

    Keys.onEscapePressed: root.dismissed()

    MouseArea { anchors.fill: parent } // keep clicks off the scrim

    Flickable {
      id: flick
      anchors { fill: parent; margins: Theme.space.xl }
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

      ColumnLayout {
        id: column
        width: flick.width - Theme.space.lg
        spacing: Theme.space.lg

        Text {
          text: "Profiles"
          color: Theme.foreground
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.title
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          text: "A profile remembers the layout for one set of monitors, like \"laptop + desk monitor\". "
                + "When exactly those monitors are connected, Hyprland switches to it by itself, no Panorama needed. "
                + "With no matching profile, each monitor's latest saved settings apply. "
                + "Saving updates the profile that matches the monitors connected now."
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.caption
        }

        Text {
          visible: Persist.profiles.length === 0
          text: "No profiles yet."
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.body
        }

        Repeater {
          model: Persist.profiles

          Rectangle {
            id: profileCard
            required property var modelData
            required property int index
            readonly property bool matchesNow: P.matches(modelData, Hypr.monitors)

            Layout.fillWidth: true
            implicitHeight: profileColumn.implicitHeight + 2 * Theme.space.lg
            radius: Theme.radius
            color: matchesNow ? Theme.selected : Theme.alpha(Theme.foreground, 0.03)
            border.color: matchesNow ? Theme.accent : Theme.border

            ColumnLayout {
              id: profileColumn
              anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space.lg }
              spacing: Theme.space.md

              RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space.md

                TextField {
                  Layout.fillWidth: true
                  label: "Profile name"
                  text: profileCard.modelData.name
                  onCommitted: t => Persist.renameProfile(profileCard.index, t)
                }

                Text {
                  visible: profileCard.matchesNow
                  text: "matches now"
                  color: Theme.accent
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.font.caption
                }

                PButton {
                  text: "Delete"
                  onClicked: Persist.deleteProfile(profileCard.index)
                }
              }

              Repeater {
                model: profileCard.modelData.monitors

                RowLayout {
                  required property var modelData
                  Layout.fillWidth: true
                  spacing: Theme.space.md

                  Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.monitorLabel(modelData)
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.body
                  }

                  Text {
                    text: "workspaces"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.caption
                  }

                  TextField {
                    implicitWidth: Math.round(140 * Theme.unit)
                    label: "Default workspaces"
                    placeholder: "e.g. 1 2 3"
                    text: P.workspacesOf(profileCard.modelData, modelData.match).join(" ")
                    onCommitted: t => Persist.setProfileWorkspaces(profileCard.index, modelData.port, t)
                  }
                }
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Theme.space.md

          TextField {
            id: newName
            Layout.fillWidth: true
            label: "New profile name"
            placeholder: Persist.activeProfile ? "A profile already covers these monitors" : "Name for this setup, e.g. Desk"
            enabled: !Persist.activeProfile
          }

          PButton {
            text: "Add for these monitors"
            enabled: !Persist.activeProfile && Hypr.monitors.length > 0
            onClicked: {
              Persist.addProfile(newName.text)
              newName.text = ""
            }
          }
        }

        Text {
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          text: "Changes here are written with Save… (Ctrl+S). Omarchy's clamshell mode still decides about the laptop panel while the lid is closed."
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.caption
        }

        RowLayout {
          Layout.alignment: Qt.AlignRight
          spacing: Theme.space.md

          PButton {
            visible: Persist.profilesEdited
            text: "Undo profile edits"
            onClicked: Persist.resetProfiles()
          }

          PButton {
            text: "Close"
            checked: true
            onClicked: root.dismissed()
          }
        }
      }
    }
  }
}
