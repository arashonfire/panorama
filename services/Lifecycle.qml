pragma Singleton
import QtQuick
import Quickshell

// Whether Panorama is in use, for the services that poll. Standalone it always
// is: the process lives exactly as long as the window. As an Omarchy shell
// plugin the singletons outlive the panel, so polling pauses while it is closed
// -- unless an apply or a save is still settling -- and everything is read
// afresh when it opens again. Written to, never reads another service, so
// every service can depend on it without a cycle.
Singleton {
  id: root

  // Set by Panel.qml; shell.qml leaves it on.
  property bool open: true
  // Set by Apply and Persist while their flows run.
  property bool applying: false
  property bool saving: false

  readonly property bool active: open || applying || saving
}
