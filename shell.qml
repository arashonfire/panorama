// Panorama: display settings for Hyprland.
// Run with `bin/panorama` (or `qs -p <this directory>`). The app is
// Panorama.qml; Panel.qml mounts the same app inside the Omarchy shell.
import QtQuick
import Quickshell
import "services"

ShellRoot {
  Panorama {}

  // Its own instance: once nothing unconfirmed is left, quitting ends it.
  Connections {
    target: Apply
    function onReadyToQuit() { Qt.quit() }
  }
}
