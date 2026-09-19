import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import "../services"
import "../lib/monitor.js" as M
import "../lib/hdrcal.js" as C

// Calibrate a display's HDR luminance by eye: peak, full-screen and black
// level, each read off a test pattern that bin/panorama-hdr-pattern shows full
// screen on that display. What the answers mean is lib/hdrcal.js. The result
// goes into the draft like any other edit, to apply and save as usual.
Item {
  id: root

  property string name: ""
  property bool open: false
  signal dismissed()

  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../bin/panorama-hdr-pattern")).replace(/^file:\/\//, ""))
  readonly property var monitor: Hypr.byName(name)
  readonly property bool inHdr: !!monitor && M.isHdr(monitor.colorManagementPreset)
  readonly property var edid: Edid.byName[name] || null
  readonly property real edidPeak: edid && edid.luminance.max > 0 ? edid.luminance.max : 0

  property string page: "intro"    // intro, test, summary
  property var missing: []
  property bool checked: false
  property int testIndex: 0
  property var cal: null           // the current round (lib/hdrcal.js)
  property var results: ({})
  property bool showing: false
  property bool shown: false
  property string error: ""
  readonly property string test: C.TESTS[testIndex]
  readonly property var summary: C.summarize(results, edid)

  visible: open
  onOpenChanged: {
    if (!open) {
      if (showing) runner.running = false
      return
    }
    page = "intro"
    results = {}
    error = ""
    checked = false
    runner.run([helper, "check"], function (code, output) {
      root.missing = output.split("\n").filter(function (s) { return s.trim() })
      root.checked = true
    })
    card.forceActiveFocus()
  }

  function startTest(i) {
    testIndex = i
    cal = C.start(C.TESTS[i], edidPeak)
    shown = false
    error = ""
    page = "test"
  }

  function next() {
    if (testIndex + 1 < C.TESTS.length) startTest(testIndex + 1)
    else page = "summary"
  }

  function skip() {
    var r = Object.assign({}, results)
    delete r[test]
    results = r
    next()
  }

  function showPattern() {
    if (showing) return
    showing = true
    error = ""
    runner.run([helper, "show", test, name, String(cal.limit)].concat(cal.tiles.map(String)), function (code, output) {
      root.showing = false
      if (code === 0) root.shown = true
      else root.error = output.trim() || "The pattern couldn't be shown (exit " + code + ")."
    })
  }

  function pick(value) {
    var s = C.answer(cal, value)
    if (!s.done) {
      cal = s
      shown = false
      return
    }
    var r = Object.assign({}, results)
    r[test] = s
    results = r
    if (s.error) return
    next()
  }

  function use() {
    Draft.set(name, summary.fields)
    dismissed()
  }

  readonly property var instructions: ({
    peak: "Squares of rising brightness, each in a frame at the brightest level this test sends. "
          + "A display shows everything above its peak alike, so squares at or above it vanish into their frames.",
    full: "The same test with the whole screen bright. Give it about five seconds before judging: "
          + "some displays dim a bright screen gradually. It closes by itself after 30 seconds.",
    black: "Near-black squares on black. Darken the room and give your eyes a minute before judging."
  })
  readonly property var questions: ({
    peak: "Which was the first square that vanished into its frame?",
    full: "Which was the first square that vanished?",
    black: "Which was the first square you could see?"
  })

  Command { id: runner }

  Rectangle {
    anchors.fill: parent
    color: Theme.alpha(Theme.background, 0.75)
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (!root.showing) root.dismissed()
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - 2 * Theme.space.xl, Math.round(640 * Theme.unit))
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
          text: root.page === "test"
                ? "Test " + (root.testIndex + 1) + " of " + C.TESTS.length + ": " + C.TITLES[root.test]
                : "Calibrate HDR by eye"
          color: Theme.foreground
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.title
          font.bold: true
        }

        // Intro -------------------------------------------------------------

        ColumnLayout {
          visible: root.page === "intro"
          Layout.fillWidth: true
          spacing: Theme.space.md

          Repeater {
            model: [
              "Three test patterns measure what " + root.name + " really shows: its peak brightness, its brightness with the whole screen bright, and its black level. "
                + "They set the luminance Hyprland tells games and players to aim for, instead of "
                + (root.edidPeak > 0 ? "the EDID's " + Math.round(root.edidPeak) + " nits peak." : "the 10000 nits it assumes when the EDID gives none."),
              "Each pattern covers the display until you press q. Then answer here what you saw.",
              "On a TV, first turn off its own tone mapping and picture enhancements: Game mode with HDR tone mapping set to HGIG on LG and Samsung, "
                + "and no dynamic contrast. Otherwise the TV changes the patterns and the readings don't hold.",
              "Nothing changes until you apply the result."
            ]
            Text {
              required property string modelData
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              text: modelData
              color: Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.body
            }
          }

          Text {
            visible: root.checked && root.missing.length > 0 || !root.inHdr
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: !root.inHdr ? root.name + " isn't showing HDR. Switch it to an HDR preset and apply first."
                : "Needs " + root.missing.join(", ") + " (mpv shows the patterns, ImageMagick draws them)."
            color: Theme.urgent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
          }
        }

        // One test ----------------------------------------------------------

        ColumnLayout {
          visible: root.page === "test" && !!root.cal
          Layout.fillWidth: true
          spacing: Theme.space.md

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: !root.cal || root.cal.round !== "fine" ? root.instructions[root.test] || ""
                : root.test === "black" ? "A closer look: squares in smaller steps, from a bit darker than the last one that looked black to the first you could see."
                : "A closer look: squares in smaller steps, from the last one you saw to a bit past the first that vanished."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
          }

          RowLayout {
            spacing: Theme.space.md

            PButton {
              text: root.showing ? "Showing…" : root.shown ? "Show again" : "Show pattern"
              checked: !root.shown
              enabled: !root.showing
              onClicked: root.showPattern()
            }

            Text {
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              text: root.showing ? "On " + root.name + ". Press q there when you've decided." : ""
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.caption
            }
          }

          Text {
            visible: root.error.length > 0 || !!(root.results[root.test] && root.results[root.test].error)
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.error || (root.results[root.test] ? root.results[root.test].error || "" : "")
            color: Theme.urgent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
          }

          Text {
            visible: root.shown
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.questions[root.test] || ""
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
          }

          Flow {
            visible: root.shown
            Layout.fillWidth: true
            spacing: Theme.space.sm

            Repeater {
              model: root.cal ? C.choices(root.cal) : []
              PButton {
                id: choice
                required property var modelData
                text: choice.modelData.label
                onClicked: root.pick(choice.modelData.value)
              }
            }
          }
        }

        // Summary -----------------------------------------------------------

        ColumnLayout {
          visible: root.page === "summary"
          Layout.fillWidth: true
          spacing: Theme.space.md

          Repeater {
            model: [
              { key: "max_luminance", label: "Peak" },
              { key: "max_avg_luminance", label: "Average" },
              { key: "min_luminance", label: "Minimum" }
            ]
            RowLayout {
              id: row
              required property var modelData
              spacing: Theme.space.md

              Text {
                Layout.preferredWidth: Math.round(96 * Theme.unit)
                text: row.modelData.label
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
              }

              Text {
                text: C.label(row.modelData.key, root.summary.fields[row.modelData.key])
                color: root.summary.fields[row.modelData.key] === undefined ? Theme.muted : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
              }
            }
          }

          Repeater {
            model: root.summary.notes
            Text {
              required property string modelData
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              text: modelData
              color: Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.font.caption
            }
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Object.keys(root.summary.fields).length
                  ? "These go into " + root.name + "'s luminance overrides. Apply to try them, save to keep them. "
                    + "They hold for the display's current picture mode."
                  : "Nothing was measured."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
          }
        }

        RowLayout {
          Layout.alignment: Qt.AlignRight
          spacing: Theme.space.md

          PButton {
            text: "Cancel"
            onClicked: root.dismissed()
          }

          PButton {
            visible: root.page === "test"
            text: "Skip this test"
            enabled: !root.showing
            onClicked: root.skip()
          }

          PButton {
            visible: root.page === "test" && !!(root.results[root.test] && root.results[root.test].error)
            text: "Try again"
            onClicked: root.startTest(root.testIndex)
          }

          PButton {
            visible: root.page === "intro"
            text: "Start"
            checked: true
            enabled: root.checked && root.missing.length === 0 && root.inHdr
            onClicked: root.startTest(0)
          }

          PButton {
            visible: root.page === "summary"
            text: "Use these values"
            checked: true
            enabled: Object.keys(root.summary.fields).length > 0 && Apply.state === "idle"
            onClicked: root.use()
          }
        }
      }
    }
  }
}
