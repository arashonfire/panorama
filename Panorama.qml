// Panorama: display settings for Hyprland -- the window, keys, IPC and
// per-screen overlays. Two entry points mount it: app.qml runs it as its own
// Quickshell instance (`bin/panorama`), Panel.qml inside the Omarchy shell as a
// plugin. Neither decides anything here; how quitting ends is theirs
// (Apply.readyToQuit).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "services"
import "ui"

Item {
  id: app

  property string selectedName: ""
  property bool identifying: false
  property bool saveDialogOpen: false
  property bool profilesOpen: false
  property bool helpOpen: false
  readonly property bool dialogOpen: saveDialogOpen || profilesOpen || helpOpen
  readonly property var selected: Hypr.byName(selectedName)
  // Something to save: live changes, or the file doesn't match the live state.
  readonly property bool canOpenSave: Persist.canPrepareSave && (Apply.liveUnsaved || !Persist.saved)

  // Keep a valid selection: the focused monitor, else the first one.
  function ensureSelection() {
    if (Hypr.byName(selectedName)) return
    var list = Hypr.monitors
    for (var i = 0; i < list.length; i++) {
      if (list[i].focused) {
        selectedName = list[i].name
        return
      }
    }
    selectedName = list.length ? list[0].name : ""
  }

  function selectRelative(delta) {
    var list = Hypr.monitors
    if (!list.length) return
    var i = Hypr.numberOf(selectedName) - 1
    selectedName = list[(i + delta + list.length) % list.length].name
  }

  function identify() {
    identifying = true
    identifyTimer.restart()
  }

  Connections {
    target: Hypr
    function onMonitorsChanged() { app.ensureSelection() }
  }

  Timer {
    id: identifyTimer
    interval: 3000
    onTriggered: app.identifying = false
  }

  // `qs -p <dir> ipc call panorama <function> [args]` standalone; as a plugin
  // the target lives in the Omarchy shell (`qs -p $OMARCHY_PATH/shell`), and
  // only while the panel is open. The editing functions go through the same
  // Draft/Apply/Persist path as the UI, confirmation included.
  IpcHandler {
    target: "panorama"
    function show(): void { if (app.floatRuleReady) window.visible = true }
    function identify(): void { app.identify() }
    function quit(): void { Apply.quit() }

    function select(name: string): void { app.selectedName = name }
    function showTab(tab: string): void { inspector.tab = tab }
    function setEnabled(name: string, on: bool): void { Draft.setEnabled(name, on) }
    function setMode(name: string, width: int, height: int, refresh: real): void { Draft.setMode(name, width, height, refresh) }
    function setScale(name: string, scale: real): void { Draft.setScale(name, scale) }
    function setTransform(name: string, transform: int): void { Draft.setTransform(name, transform) }
    function setMirror(name: string, target: string): void { Draft.setMirror(name, target) }
    function move(name: string, x: int, y: int): void { Draft.move(name, x, y) }
    function nudge(name: string, dx: int, dy: int): void { Draft.nudge(name, dx, dy) }
    function setColor(name: string, key: string, value: string): void { Draft.setColorFromString(name, key, value) }
    function setGlobal(key: string, value: string): void { Draft.setGlobalFromString(key, value) }
    function setBrightness(name: string, percent: int): void { Brightness.set(name, percent) }
    function stepSdrBrightness(name: string, spec: string): string { return Apply.stepSdrBrightness(name, spec) }
    function setSdrBrightness(name: string, value: real): void { Apply.setSdrBrightness(name, value) }
    function reset(): void { Draft.reset() }
    function apply(): void { Apply.apply() }
    function keep(): void { Apply.keep() }
    function revert(): void { Apply.revert() }

    function setMatch(name: string, how: string): void { Persist.setMatch(name, how) }
    function preview(): string { return Persist.sectionLines.join("\n") }
    function openSave(): void { if (app.canOpenSave) app.saveDialogOpen = true }
    function closeSave(): void { app.saveDialogOpen = false }
    function openProfiles(): void { app.profilesOpen = true }
    function closeProfiles(): void { app.profilesOpen = false }

    function addProfile(name: string): void { Persist.addProfile(name) }
    function renameProfile(index: int, name: string): void { Persist.renameProfile(index, name) }
    function deleteProfile(index: int): void { Persist.deleteProfile(index) }
    function setProfileWorkspaces(index: int, monitor: string, workspaces: string): void { Persist.setProfileWorkspaces(index, monitor, workspaces) }
    function profiles(): string {
      return JSON.stringify({
        profiles: Persist.profiles,
        saved: Persist.parsed.profiles.map(function (p) { return p.name }),
        running: Persist.activeSaved ? Persist.activeSaved.name : "",
        matching: Persist.activeProfile ? Persist.activeProfile.name : "",
        edited: Persist.profilesEdited
      })
    }
    function checkConfig(): void { Persist.checkConfig(false) }
    function addRequire(): void { Persist.addRequire() }
    function save(): void { Persist.save() }
    function undoSave(): void { Persist.undo() }

    function state(): string {
      return JSON.stringify({
        phase: Apply.state,
        secondsLeft: Apply.secondsLeft,
        message: Apply.message,
        issues: Apply.issues,
        liveUnsaved: Apply.liveUnsaved,
        changes: Draft.changes,
        draft: Draft.pending.map(function (c) { return { name: c.name, enabled: c.enabled, mirror: c.mirror, x: c.x, y: c.y } }),
        globalChanges: Draft.globalLines,
        errors: Draft.errors,
        appliedRules: Apply.appliedRules,
        appliedGlobals: Apply.appliedGlobals,
        globals: Globals.values,
        brightness: Brightness.values,
        ui: {
          selected: app.selectedName,
          tab: inspector.tab,
          help: app.helpOpen,
          save: app.saveDialogOpen,
          profiles: app.profilesOpen
        },
        persist: {
          path: Persist.path,
          state: Persist.state,
          saved: Persist.saved,
          hasSection: Persist.parsed.hasBlock,
          configState: Persist.configState,
          error: Persist.parsed.error,
          message: Persist.message,
          messageIsError: Persist.messageIsError,
          lastBackup: Persist.lastBackup,
          conflicts: Persist.conflicts
        }
      })
    }
  }

  Variants {
    model: Quickshell.screens
    IdentifyOverlay { shown: app.identifying }
  }

  Variants {
    model: Quickshell.screens
    ConfirmOverlay {}
  }

  // Hyprland tiles a Quickshell FloatingWindow, so float it with a runtime rule
  // before the window first maps. A config reload drops the rule; every start
  // adds it again. bin/panorama adds it ahead of a standalone launch as well,
  // but a plugin is summoned by the Omarchy shell and never goes through it.
  property bool floatRuleReady: false

  Process {
    running: true
    command: ["sh", "-c", "hyprctl eval \"$1\" >/dev/null 2>&1; exit 0", "sh",
      'hl.window_rule({ name = "panorama-float", match = { class = "^org\\\\.quickshell$", title = "^Panorama$" }, float = true, center = true, size = { 1100, 720 } })']
    onExited: app.floatRuleReady = true
  }

  FloatingWindow {
    id: window
    title: "Panorama"
    visible: app.floatRuleReady
    implicitWidth: Math.round(1100 * Theme.unit)
    implicitHeight: Math.round(720 * Theme.unit)
    minimumSize: Qt.size(Math.round(820 * Theme.unit), Math.round(520 * Theme.unit))
    color: Theme.background
    onClosed: Apply.quit()

    Item {
      id: main
      anchors.fill: parent
      focus: true

      Keys.onPressed: event => {
        var key = event.key
        var ctrl = event.modifiers & Qt.ControlModifier
        var alt = event.modifiers & Qt.AltModifier
        var shift = event.modifiers & Qt.ShiftModifier
        var enter = key === Qt.Key_Return || key === Qt.Key_Enter
        var arrow = key === Qt.Key_Left ? [-1, 0] : key === Qt.Key_Right ? [1, 0]
                  : key === Qt.Key_Up ? [0, -1] : key === Qt.Key_Down ? [0, 1] : null
        if (Apply.state === "confirming") {
          if (enter) Apply.keep()
          else if (key === Qt.Key_Escape) Apply.revert()
          else return
        } else if (key === Qt.Key_Escape) Apply.quit()
        else if (enter && ctrl) Apply.apply()
        else if (key === Qt.Key_S && ctrl) { if (app.canOpenSave) app.saveDialogOpen = true }
        else if (key === Qt.Key_P && ctrl) app.profilesOpen = true
        else if (ctrl && key >= Qt.Key_1 && key <= Qt.Key_4) inspector.tab = ["settings", "color", "details", "global"][key - Qt.Key_1]
        else if (arrow && alt) {
          var stepPx = shift ? 10 : 100
          if (Apply.state === "idle") Draft.nudge(app.selectedName, arrow[0] * stepPx, arrow[1] * stepPx)
        }
        else if (key === Qt.Key_Left || key === Qt.Key_Up) app.selectRelative(-1)
        else if (key === Qt.Key_Right || key === Qt.Key_Down) app.selectRelative(1)
        else if (key === Qt.Key_I && !ctrl) app.identify()
        else if (key === Qt.Key_R && ctrl) { Hypr.refresh(); Persist.checkConfig(false) }
        else if (key === Qt.Key_Question || key === Qt.Key_F1) app.helpOpen = true
        else return
        event.accepted = true
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space.xl
        spacing: Theme.space.lg
        // Keep Tab inside an open dialog.
        enabled: !app.dialogOpen

        RowLayout {
          Layout.fillWidth: true
          spacing: Theme.space.md

          ColumnLayout {
            spacing: Theme.space.xs

            Text {
              text: "Panorama"
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.heading
              font.bold: true
            }

            Text {
              readonly property int active: Hypr.monitors.filter(function (m) { return !m.disabled }).length
              text: Hypr.monitors.length + (Hypr.monitors.length === 1 ? " display" : " displays")
                    + (active !== Hypr.monitors.length ? " · " + active + " active" : "")
              color: Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.caption
            }
          }

          Item { Layout.fillWidth: true }

          Rectangle {
            id: status
            readonly property bool attention: !!Persist.parsed.error || !Persist.configLoads
            readonly property bool unsaved: Apply.liveUnsaved || (Persist.parsed.hasBlock && !Persist.saved)
            implicitWidth: statusLabel.implicitWidth + 2 * Theme.space.md
            implicitHeight: statusLabel.implicitHeight + 2 * Theme.space.xs
            radius: Theme.radius
            color: "transparent"
            border.color: attention ? Theme.urgent : unsaved ? Theme.alpha(Theme.accent, 0.6) : Theme.border

            Text {
              id: statusLabel
              anchors.centerIn: parent
              text: Persist.parsed.error ? "monitors.lua needs attention"
                  : Persist.configState === "legacy" ? "hyprland.conf isn't supported"
                  : !Persist.configLoads ? "monitors.lua isn't loaded"
                  : Persist.busy ? "Saving…"
                  : Apply.liveUnsaved ? "Live · not saved"
                  : Persist.saved ? "Saved"
                  : Persist.parsed.hasBlock ? "Not saved"
                  : "Not saved by Panorama yet"
              color: status.attention ? Theme.urgent : status.unsaved ? Theme.accent : Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.caption
            }
          }

          Rectangle {
            visible: !!Persist.activeSaved
            implicitWidth: profileLabel.implicitWidth + 2 * Theme.space.md
            implicitHeight: profileLabel.implicitHeight + 2 * Theme.space.xs
            radius: Theme.radius
            color: "transparent"
            border.color: Theme.border

            Text {
              id: profileLabel
              anchors.centerIn: parent
              text: Persist.activeSaved ? "Profile: " + Persist.activeSaved.name : ""
              color: Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.caption
            }
          }

          PButton {
            text: "Profiles…"
            onClicked: app.profilesOpen = true
          }

          PButton {
            text: "Save…"
            enabled: app.canOpenSave
            onClicked: app.saveDialogOpen = true
          }

          PButton {
            text: "Identify"
            onClicked: app.identify()
          }

          PButton {
            text: "Refresh"
            onClicked: { Hypr.refresh(); Persist.checkConfig(false) }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Theme.space.lg

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space.lg

            LayoutCanvas {
              Layout.fillWidth: true
              Layout.fillHeight: true
              selectedName: app.selectedName
              onSelect: name => app.selectedName = name
            }

            BrightnessStrip {
              Layout.fillWidth: true
            }
          }

          Inspector {
            id: inspector
            Layout.preferredWidth: Math.round(400 * Theme.unit)
            Layout.fillHeight: true
            monitor: app.selected
            monitors: Hypr.monitors
          }
        }

        ActionBar {
          Layout.fillWidth: true
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Theme.space.lg

          Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: Persist.parsed.error || Hypr.error
                  || ("Hyprland " + (Hypr.version || "?") + " · " + Persist.displayPath + " · updated " + Qt.formatTime(Hypr.updatedAt, "HH:mm:ss"))
            color: Persist.parsed.error || Hypr.error ? Theme.urgent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
          }

          Text {
            text: "? shortcuts · Ctrl+Enter apply · Ctrl+S save · Esc close"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
          }
        }
      }

      KeysHelp {
        anchors.fill: parent
        open: app.helpOpen
        onDismissed: {
          app.helpOpen = false
          main.forceActiveFocus()
        }
      }

      ProfilesDialog {
        anchors.fill: parent
        open: app.profilesOpen
        onDismissed: {
          app.profilesOpen = false
          main.forceActiveFocus()
        }
      }

      SaveDialog {
        anchors.fill: parent
        open: app.saveDialogOpen
        onDismissed: {
          app.saveDialogOpen = false
          main.forceActiveFocus()
        }
      }
    }
  }
}
