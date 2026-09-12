// Panorama as an Omarchy shell plugin (kind "panel"). The host loads this on
// summon, calls close() on hide, then destroys it -- so the window lives exactly
// as long as this item. Panorama's singletons do not: they belong to the
// shell's QML engine and outlive every summon.
import QtQuick
import "services"

Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property bool opened: false

  function open(payloadJson) {
    opened = true
  }

  // The host's hide, including the one requested below.
  function close() {
    if (!opened) return
    opened = false
    // Put back anything unconfirmed. Apply outlives this item, so the revert
    // still finishes after the host has torn the panel down.
    Apply.quit()
  }

  Panorama {}

  // Escape, the window's close button, or IPC quit: inside the shared shell
  // that means hiding the panel, never ending the process.
  Connections {
    target: Apply
    function onReadyToQuit() {
      if (!root.opened) return
      root.opened = false
      if (root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "")
    }
  }
}
