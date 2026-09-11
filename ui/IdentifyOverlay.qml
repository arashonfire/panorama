import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import "../lib/monitor.js" as M

// Big number card centred on one physical screen, matching the numbers on the
// layout canvas. With no anchors, layer-shell centres the surface.
PanelWindow {
  id: root

  required property var modelData
  property bool shown: false
  readonly property var monitor: Hypr.byName(modelData.name)

  screen: modelData
  visible: shown && monitor !== null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "panorama-identify"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight

  Rectangle {
    id: card
    implicitWidth: Math.max(Math.round(320 * Theme.unit), details.implicitWidth + 2 * Theme.space.xl * 2)
    implicitHeight: details.implicitHeight + 2 * Theme.space.xl * 1.5
    radius: Theme.radius
    color: Theme.alpha(Theme.background, 0.94)
    border.color: Theme.accent
    border.width: 2

    Column {
      id: details
      anchors.centerIn: parent
      spacing: Theme.space.sm

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.monitor ? Hypr.numberOf(root.monitor.name) : ""
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.hero
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.monitor ? root.monitor.name : ""
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.heading
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.monitor ? M.displayName(root.monitor) : ""
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.monitor
              ? root.monitor.width + "×" + root.monitor.height + " @ " + M.formatRefresh(root.monitor.refreshRate) + " · scale " + M.formatScale(root.monitor.scale)
              : ""
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
      }
    }
  }
}
