import QtQuick
import QtQuick.Layouts
import "../services"

// Bottom bar: pending changes with Reset/Apply, the keep/revert prompt while
// an applied change waits for confirmation, save progress, and the outcome of
// the last action.
Rectangle {
  id: root

  readonly property string phase: Apply.state
  readonly property bool confirming: phase === "confirming"
  readonly property bool pending: phase === "idle" && Draft.dirty
  readonly property bool persistNewer: Persist.messageAt > Apply.messageAt
  readonly property string lastMessage: persistNewer ? Persist.message : Apply.message
  readonly property bool lastIsError: persistNewer ? Persist.messageIsError : Apply.messageIsError

  readonly property string headline: {
    if (confirming) return "Keep these settings? Reverting in " + Apply.secondsLeft + " s"
    if (phase === "applying") return "Applying…"
    if (phase === "reverting") return "Reverting…"
    if (Persist.state === "saving") return "Saving " + Persist.displayPath + "…"
    if (Persist.state === "checking") return "Reloading Hyprland and checking the result…"
    if (Persist.state === "restoring") return "Restoring the previous " + Persist.displayPath + "…"
    if (pending) {
      var parts = []
      if (Draft.changes.length) parts.push(Draft.changes.length === 1 ? "1 display changed" : Draft.changes.length + " displays changed")
      if (Draft.globalLines.length) parts.push("global settings changed")
      return parts.join(", ").replace(/^./, function (c) { return c.toUpperCase() })
    }
    return lastMessage || "No pending changes"
  }

  readonly property string detail: {
    if (confirming) return Apply.issues.length ? Apply.issues.join("\n") : "Enter keeps · Esc reverts"
    if (pending) {
      if (Draft.errors.length) return Draft.errors.join("\n")
      return Draft.changes.map(function (c) { return c.name + ": " + c.lines.join(" · ") })
        .concat(Draft.globalLines.length ? ["Global: " + Draft.globalLines.join(" · ")] : [])
        .join("\n")
    }
    return ""
  }

  implicitHeight: content.implicitHeight + 2 * Theme.space.md
  radius: Theme.radius
  color: confirming ? Theme.alpha(Theme.accent, 0.1) : Theme.alpha(Theme.foreground, 0.03)
  border.color: confirming || pending ? Theme.alpha(Theme.accent, 0.6) : Theme.border

  RowLayout {
    id: content
    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Theme.space.md }
    spacing: Theme.space.lg

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Theme.space.xs

      Text {
        Layout.fillWidth: true
        text: root.headline
        wrapMode: Text.Wrap
        color: !root.pending && !root.confirming && root.lastIsError ? Theme.urgent
             : root.confirming ? Theme.accent : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
        font.bold: root.pending || root.confirming
      }

      Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.detail
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        color: root.pending && Draft.errors.length ? Theme.urgent : Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.caption
      }
    }

    PButton {
      visible: root.pending
      text: "Reset"
      onClicked: Draft.reset()
    }

    PButton {
      visible: root.pending
      text: "Apply"
      checked: true
      enabled: Draft.errors.length === 0
      onClicked: Apply.apply()
    }

    PButton {
      visible: root.confirming
      text: "Revert"
      onClicked: Apply.revert()
    }

    PButton {
      visible: root.confirming
      text: "Keep changes"
      checked: true
      onClicked: Apply.keep()
    }

    PButton {
      visible: !root.pending && !root.confirming && Persist.canUndo && root.persistNewer
      text: "Undo save"
      onClicked: Persist.undo()
    }
  }
}
