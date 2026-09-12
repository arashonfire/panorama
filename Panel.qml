// Panorama as an Omarchy shell plugin (kind "panel"). The host loads this on
// summon, calls close() on hide, then destroys it -- so the window lives exactly
// as long as this item. Panorama's singletons do not: they belong to the
// shell's QML engine and outlive every summon, which is why their polling
// follows `opened` (Lifecycle) and each summon starts from a clean draft.
import QtQuick
import "services"

Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property bool opened: false
  onOpenedChanged: Lifecycle.open = opened

  function open(payloadJson) {
    if (opened) return
    // Hidden mid-confirm and reopened before the revert landed: that revert
    // must not close this new panel when it does.
    Apply.cancelQuit()
    // What a fresh launch starts with: no leftover edits from the last time.
    // A revert still settling resets the draft itself when it lands.
    if (Apply.state === "idle") Draft.reset()
    if (Persist.state === "idle") Persist.resetProfiles()
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

  Component.onDestruction: Lifecycle.open = false

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
