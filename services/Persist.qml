pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/block.js" as B
import "../lib/draft.js" as D
import "../lib/profiles.js" as P

// Saves the live layout into Panorama's section of monitors.lua. The file work
// (backup first, atomic replace, restore) is bin/panorama-persist's job; this
// service decides what to write, reloads Hyprland and checks the result. If
// the reload reports new config errors, the backup goes straight back.
Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../bin/panorama-persist")).replace(/^file:\/\//, ""))
  readonly property string path: Quickshell.env("PANORAMA_MONITORS_FILE")
    || ((Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/hypr/monitors.lua")
  readonly property string displayPath: path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path

  property string text: ""
  // Per-connector "port" / "monitor" choices made in the UI.
  property var matchBy: ({})
  property string state: "idle" // idle | saving | checking | restoring
  property string message: ""
  property bool messageIsError: false
  property date messageAt: new Date(0)
  // The file as it was before the last save this session.
  property string lastBackup: ""

  readonly property var parsed: B.parse(text)
  // Global options Panorama manages: the saved ones plus any applied since.
  readonly property var globalsToSave: Object.assign({}, B.savedGlobals(parsed), Apply.appliedGlobals)

  // Profiles as they'll be saved: the file's, plus edits made in the UI.
  property var profiles: []
  // Set by any edit, so a file reload doesn't overwrite the working copy.
  property bool _profilesEdited: false
  // Whether the working copy actually differs from the file.
  readonly property bool profilesEdited: JSON.stringify(profiles) !== JSON.stringify(parsed.profiles)
  // The saved profile Hyprland is running now (matches the connected monitors).
  readonly property var activeSaved: P.active(parsed.profiles, Hypr.monitors)
  // The edited profile that matches; saving refreshes it with the current layout.
  readonly property var activeProfile: P.active(profiles, Hypr.monitors)

  // What a monitor asked for: a rule applied this session, else the running
  // profile's rule, else (in lib/block.js) its saved rule.
  function _requested(m) {
    return Apply.appliedRules[m.name] || P.ruleFor(activeSaved, m) || null
  }
  function _how(m) { return B.howFor(m, Hypr.monitors, parsed, matchBy) }
  function _rule(m) { return B.ruleTable(m, Hypr.monitors, parsed, _how(m), _requested(m)) }

  readonly property var profilesToSave: profiles.map(function (p) {
    return p === root.activeProfile ? P.capture(null, Hypr.monitors, root._rule, root._how, p) : p
  })
  readonly property var lines: B.body(Hypr.monitors, parsed, matchBy, _requested, globalsToSave, profilesToSave)

  function addProfile(name) {
    if (activeProfile || !Hypr.monitors.length) return
    name = String(name || "").trim() || "Profile " + (profiles.length + 1)
    profiles = profiles.concat([P.capture(name, Hypr.monitors, _rule, _how)])
    _profilesEdited = true
  }

  function renameProfile(index, name) {
    name = String(name || "").trim()
    if (!name || !profiles[index]) return
    var next = profiles.slice()
    next[index] = Object.assign({}, next[index], { name: name })
    profiles = next
    _profilesEdited = true
  }

  function deleteProfile(index) {
    if (!profiles[index]) return
    var next = profiles.slice()
    next.splice(index, 1)
    profiles = next
    _profilesEdited = true
  }

  // `text`: "1, 2, 3" for the monitor at connector `name` in that profile.
  function setProfileWorkspaces(index, name, text) {
    var p = profiles[index]
    if (!p) return
    var mon = Hypr.byName(name)
    var entry = null
    p.monitors.forEach(function (w) { if (mon ? B.selects(w.match, mon) : w.port === name) entry = w })
    if (!entry) return
    var next = profiles.slice()
    next[index] = P.setWorkspaces(p, entry.match, text)
    profiles = next
    _profilesEdited = true
  }

  function resetProfiles() {
    profiles = parsed.profiles
    _profilesEdited = false
  }
  readonly property var sectionLines: B.section(lines)
  readonly property bool saved: !parsed.error && B.isSaved(lines, parsed)
  readonly property var conflicts: B.conflicts(Hypr.monitors, parsed)
  readonly property bool busy: state !== "idle"
  readonly property bool canSave: !busy && Apply.state === "idle" && !Draft.dirty && !parsed.error && Hypr.monitors.length > 0
  readonly property bool canUndo: !busy && Apply.state === "idle" && lastBackup !== ""

  property var _errorsBefore: []
  property var _snapshot: []
  property bool _isSave: false

  function matchOf(name) {
    var mon = Hypr.byName(name)
    if (!mon) return "port"
    var how = matchBy[name] || B.matchFor(mon, Hypr.monitors, parsed)
    return how === "monitor" && !B.canMatchByMonitor(mon, Hypr.monitors) ? "port" : how
  }

  // How the monitor is matched in the file right now, or "" if it isn't there.
  function savedMatch(name) {
    var mon = Hypr.byName(name)
    var rule = mon ? B.savedRule(mon, parsed) : null
    return rule ? (rule.output.indexOf("desc:") === 0 ? "monitor" : "port") : ""
  }

  // What the monitor asked for in the file: the running profile's rule, else
  // its saved rule, as a table; or null.
  function savedRequestFor(mon) {
    return P.ruleFor(activeSaved, mon) || B.savedRequest(mon, parsed)
  }

  function canMatchByMonitor(name) {
    var mon = Hypr.byName(name)
    return !!mon && B.canMatchByMonitor(mon, Hypr.monitors)
  }

  function setMatch(name, how) {
    var next = Object.assign({}, matchBy)
    next[name] = how
    matchBy = next
  }

  function save() {
    if (!canSave) return
    var content
    try {
      content = B.render(text, lines)
    } catch (e) {
      _say("Couldn't prepare " + displayPath + ": " + e.message, true)
      return
    }
    _snapshot = JSON.parse(JSON.stringify(Hypr.monitors))
    _isSave = true
    state = "saving"
    runner.run(["hyprctl", "-j", "configerrors"], function (code, output) {
      root._errorsBefore = root._errors(output)
      runner.run([root.helper, "save"], function (code, output) {
        if (code !== 0) {
          root.state = "idle"
          root._say("Couldn't save " + root.displayPath + ": " + output.trim(), true)
          return
        }
        root.lastBackup = output.trim().split("\n").pop()
        // The file now holds the edited profiles; take them from there again.
        root._profilesEdited = false
        file.reload()
        root._reloadAndCheck()
      }, content)
    })
  }

  function undo() {
    if (!canUndo) return
    _isSave = false
    state = "restoring"
    runner.run([helper, "restore", lastBackup], function (code, output) {
      if (code !== 0) {
        root.state = "idle"
        root._say("Couldn't restore the backup: " + output.trim(), true)
        return
      }
      root.lastBackup = ""
      root._profilesEdited = false
      file.reload()
      root._reloadAndCheck()
    })
  }

  function _say(text, isError) {
    message = text
    messageIsError = isError
    messageAt = new Date()
  }

  function _errors(output) {
    try {
      return JSON.parse(output).filter(function (e) { return typeof e === "string" && e.trim().length > 0 })
    } catch (e) {
      return []
    }
  }

  function _reloadAndCheck() {
    state = "checking"
    Apply.expectReload()
    Apply.liveUnsaved = false
    runner.run(["hyprctl", "reload"], function () { settle.restart() })
  }

  // New config errors after a save: put the old file back and reload again.
  function _rollback(added) {
    state = "restoring"
    var backup = lastBackup
    runner.run([helper, "restore", backup], function () {
      root.lastBackup = ""
      file.reload()
      Apply.expectReload()
      runner.run(["hyprctl", "reload"], function () {
        root.state = "idle"
        root._say("Hyprland reported new config errors after saving (" + added.join("; ") + "), so the previous "
                  + root.displayPath + " was put back.", true)
      })
    })
  }

  Command {
    id: runner
  }

  // Give Hyprland time to re-read the files and re-apply the rules.
  Timer {
    id: settle
    interval: 1200
    onTriggered: runner.run(["hyprctl", "-j", "configerrors"], function (code, output) {
      var added = root._errors(output).filter(function (e) { return root._errorsBefore.indexOf(e) < 0 })
      if (root._isSave && added.length && root.lastBackup) {
        root._rollback(added)
        return
      }
      Hypr.refresh()
      verify.restart()
    })
  }

  Timer {
    id: verify
    interval: 600
    onTriggered: {
      root.state = "idle"
      if (!root._isSave) {
        root._say("Restored " + root.displayPath + " from before the last save.", false)
        return
      }
      var before = D.expectedAfterReload(root._snapshot, function (m) { return root.savedRequestFor(m) })
      var issues = D.verify(before, Hypr.monitors)
      if (issues.length) root._say("Saved to " + root.displayPath + ", but after reloading: " + issues.join(" "), true)
      else root._say("Saved to " + root.displayPath + ". The previous file is backed up.", false)
    }
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.text = text()
      if (!root._profilesEdited) root.profiles = root.parsed.profiles
    }
  }
}
