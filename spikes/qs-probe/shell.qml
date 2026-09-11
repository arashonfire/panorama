// Spike: FloatingWindow + per-screen overlay + Hyprland events + Process/FileView.
// Run: qs -p spikes/qs-probe   (quits by itself after 20 s)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name.indexOf("monitor") >= 0 || event.name === "configreloaded")
        console.log("RAW", event.name, event.data)
    }
  }

  Process {
    running: true
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      onStreamFinished: {
        var m = JSON.parse(text)
        console.log("PROCESS monitors:", m.map(x => x.name + " cm=" + x.colorManagementPreset).join(", "))
      }
    }
  }

  FileView {
    id: probeFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/panorama-probe.txt"
    blockLoading: true
    printErrors: false
  }

  Component.onCompleted: {
    probeFile.setText("written by FileView\n")
    console.log("SCREENS", Quickshell.screens.map(s => s.name + " " + s.width + "x" + s.height + " dpr=" + s.devicePixelRatio).join(", "))
    console.log("HYPR monitors", Hyprland.monitors.values.map(m => m.name + " scale=" + m.scale).join(", "))
  }

  FloatingWindow {
    title: "panorama-probe"
    implicitWidth: 720
    implicitHeight: 420
    color: "#1e1e22"
    onWidthChanged: console.log("WINDOW size", width, height)

    Text {
      anchors.centerIn: parent
      color: "white"
      font.pixelSize: 22
      horizontalAlignment: Text.AlignHCenter
      text: "Panorama probe\nscreens: " + Quickshell.screens.length
            + "\nhyprland monitors: " + Hyprland.monitors.values.length
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; left: true }
      margins { top: 60; left: 60 }
      implicitWidth: 360
      implicitHeight: 180
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "panorama-identify"

      Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#dd000000"
        Text {
          anchors.centerIn: parent
          color: "white"
          font.pixelSize: 56
          font.bold: true
          text: modelData.name
        }
      }
    }
  }

  Timer {
    interval: 20000
    running: true
    onTriggered: Qt.quit()
  }
}
