pragma Singleton
import QtQuick
import Quickshell
import "../lib/draft.js" as D
import "../lib/globals.js" as G
import "../lib/brightness.js" as Br

// Applies the draft live and guards it: the current state is remembered
// first, every screen asks "Keep these settings?", and without an answer in
// `timeout` seconds the previous state is re-applied. Nothing is written to
// disk here.
Singleton {
  id: root

  readonly property int timeout: 15
  property string state: "idle" // idle | applying | confirming | reverting
  property int secondsLeft: 0
  property var issues: []
  property string message: ""
  property bool messageIsError: false
  property date messageAt: new Date(0)
  // Applied and kept, but only live: a config reload brings back the files.
  property bool liveUnsaved: false
  // Rules and global options applied and kept this session: what was last
  // asked for. Cleared on every config reload, when the files are the truth.
  property var appliedRules: ({})
  property var appliedGlobals: ({})

  property var _snapshot: []
  property var _before: []
  property var _requested: []
  property var _globalsBefore: ({})
  property var _globalsAfter: ({})
  // Omarchy's laptop-panel flag: what it said before the apply ("on"/"off", or
  // "absent" off Omarchy) and what this apply changed it to ("" when untouched).
  property string _internalFlagBefore: ""
  property string _internalFlagWritten: ""
  property string _internalFlagPanel: ""
  property int _logStart: -1
  property bool _quitAfter: false
  property bool _expectReload: false

  readonly property string _log: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/hyprland.log"
  readonly property string _internalHelper: decodeURIComponent(String(Qt.resolvedUrl("../bin/panorama-omarchy-internal")).replace(/^file:\/\//, ""))

  // Someone (Persist) is about to reload Hyprland on purpose.
  function expectReload() {
    _expectReload = true
  }

  function apply() {
    if (state !== "idle" || !Draft.dirty || Draft.errors.length) return
    _snapshot = JSON.parse(JSON.stringify(Hypr.monitors))
    _before = Draft.base
    // Revert and verification cover the same set, pinned monitors included.
    _requested = Draft.changes.length ? D.applySet(Draft.pending, Draft.changes) : []
    _globalsAfter = Draft.globalChanges
    var before = {}
    Object.keys(_globalsAfter).forEach(function (k) { before[k] = Globals.values[k] })
    _globalsBefore = before
    issues = []
    state = "applying"
    // The flag goes first: a laptop panel disabled without it is switched back
    // on by Omarchy's watcher within a couple of seconds, mid-countdown.
    _setInternalFlag(D.internalFlag(Draft.pending), function () {
      // Remember where the log ends, to spot VRR refusals caused by this apply.
      logRunner.run(["sh", "-c", "wc -l < \"$1\"", "sh", root._log], function (code, output) {
        root._logStart = code === 0 ? parseInt(output, 10) : -1
        root._send(root._requested, root._before, root._globalsAfter, function (ok, output) {
          if (!ok) {
            // Statements before the failing one already ran, so undo them.
            root._revert("Hyprland rejected the change: " + output, true, true)
            return
          }
          root.secondsLeft = root.timeout
          root.state = "confirming"
          countdown.restart()
          settle.restart()
        })
      })
    })
  }

  // Brings Omarchy's laptop-panel flag in line with `want` (from
  // D.internalFlag), remembering what it said so a revert can put it back.
  // A no-op when there is no laptop panel, off Omarchy, or when it already agrees.
  function _setInternalFlag(want, callback) {
    _internalFlagBefore = ""
    _internalFlagWritten = ""
    _internalFlagPanel = want ? want.name : ""
    if (!want) {
      callback()
      return
    }
    flagRunner.run([_internalHelper, "state"], function (code, output) {
      var now = code === 0 ? output.trim() : "absent"
      var wanted = want.off ? "off" : "on"
      root._internalFlagBefore = now
      if (now === "absent" || now === wanted) {
        callback()
        return
      }
      root._internalFlagWritten = wanted
      root._writeInternalFlag(wanted, callback)
    })
  }

  function _writeInternalFlag(value, callback) {
    flagRunner.run(value === "off" ? [_internalHelper, "off", _internalFlagPanel] : [_internalHelper, "on"],
                   function () { callback() })
  }

  // Puts the flag back as it was, so an unconfirmed change leaves nothing behind.
  function _restoreInternalFlag(callback) {
    if (!_internalFlagWritten) {
      callback()
      return
    }
    _internalFlagWritten = ""
    _writeInternalFlag(_internalFlagBefore, callback)
  }

  function keep() {
    if (state !== "confirming") return
    countdown.stop()
    state = "idle"
    liveUnsaved = true
    var rules = Object.assign({}, appliedRules)
    _requested.forEach(function (c) { rules[c.name] = D.toRule(c) })
    appliedRules = rules
    appliedGlobals = Object.assign({}, appliedGlobals, _globalsAfter)
    _internalFlagWritten = ""
    Draft.reset()
    _say(issues.length
         ? "Applied with Hyprland's adjustments. Not saved yet."
         : "Applied. Not saved yet: save to keep it after a reload or restart.", false)
  }

  // Saying no, or not answering, drops the draft too: the monitors are back as
  // they were, so a pending edit left behind would have the app contradict the
  // screen, and only Reset would clear it. A rejected apply keeps it, because
  // nothing was applied and the request is probably worth adjusting.
  function revert() {
    if (state !== "confirming") return
    _revert("Reverted to the previous settings.", false)
  }

  // SDR brightness of a monitor in HDR, the brightness control while in HDR:
  // from the brightness keys (`panorama-brightness key --hdr`) and the Settings
  // slider. Applied at once, with no countdown, because it's as harmless as a
  // backlight change; newest value wins while a slider moves.
  property var _sdrNext: ({})
  property var _sdrQueue: ({})

  // Returns the new value, or "" if nothing changed.
  function stepSdrBrightness(name, spec) {
    if (state !== "idle") return ""
    var base = Draft.baseOf(name)
    if (!base || !base.enabled) return ""
    var current = _sdrNext[name] !== undefined ? _sdrNext[name] : base.sdrbrightness
    var value = Br.sdrStep(current, spec)
    if (value === null) return ""
    setSdrBrightness(name, value)
    return String(value)
  }

  function setSdrBrightness(name, value) {
    if (state !== "idle") return
    value = Number(Math.max(Br.SDR_MIN, Math.min(Br.SDR_MAX, value)).toFixed(2))
    var next = Object.assign({}, _sdrNext)
    next[name] = value
    _sdrNext = next
    var queue = Object.assign({}, _sdrQueue)
    queue[name] = value
    _sdrQueue = queue
    _sendSdr()
  }

  function _sendSdr() {
    if (sdrRunner.running) return
    var names = Object.keys(_sdrQueue)
    if (!names.length) return
    var name = names[0], value = _sdrQueue[name]
    var queue = Object.assign({}, _sdrQueue)
    delete queue[name]
    _sdrQueue = queue
    var base = Draft.baseOf(name)
    if (!base || !base.enabled) {
      _sendSdr()
      return
    }
    var rule = D.toRule(D.merge(base, { sdrbrightness: value }))
    sdrRunner.run(["hyprctl", "eval", D.script([rule])], function (code, output) {
      if (code === 0 && output.trim().indexOf("error") !== 0) {
        var rules = Object.assign({}, root.appliedRules)
        rules[name] = rule
        root.appliedRules = rules
        root.liveUnsaved = true
        Hypr.refresh()
      }
      root._sendSdr()
    })
  }

  // Nothing unconfirmed is left live and Panorama can go. What going means is
  // up to whoever hosts it: shell.qml ends the process, while the Omarchy
  // plugin (Panel.qml) only hides its panel -- Qt.quit() there would take the
  // whole desktop shell down with it.
  signal readyToQuit()

  // Never leave an unconfirmed change behind: revert first, then quit.
  function quit() {
    if (state === "idle") {
      readyToQuit()
      return
    }
    _quitAfter = true
    if (state === "confirming") revert()
  }

  function _say(text, isError) {
    message = text
    messageIsError = isError
    messageAt = new Date()
  }

  function _revert(text, isError, keepDraft) {
    countdown.stop()
    settle.stop()
    verify.stop()
    state = "reverting"
    var names = _requested.map(function (c) { return c.name })
    var before = _before.filter(function (c) { return names.indexOf(c.name) >= 0 })
    _restoreInternalFlag(function () {
      root._sendRevert(before, text, isError, keepDraft)
    })
  }

  function _sendRevert(before, text, isError, keepDraft) {
    _send(before, _requested, _globalsBefore, function (ok) {
      if (!ok) {
        // Re-applying the previous state failed; fall back to the config files.
        root._expectReload = true
        Quickshell.execDetached(["hyprctl", "reload"])
      }
      root.state = "idle"
      root.issues = []
      if (!keepDraft) Draft.reset()
      root._say(text, isError)
      root._restoreWorkspaces(root._snapshot.filter(function (m) { return !m.disabled }).map(function (m) { return m.name }))
      if (root._quitAfter) quitDelay.start()
    })
  }

  // Complete runtime rules for `configs` plus the global options, as one
  // script. Monitors whose VRR setting changes compared to `previous` get a
  // nudged rule first, because Hyprland ignores vrr-only rule changes.
  function _send(configs, previous, globals, callback) {
    var rules = configs.map(function (c) { return D.toRule(c) })
    var main = [D.script(rules), G.script(globals)].filter(function (s) { return s.length > 0 }).join("\n")
    if (!main) {
      callback(true, "")
      return
    }
    var vrr = D.vrrChanged(previous, configs)
    if (!vrr.length) {
      _eval(main, callback)
      return
    }
    var nudges = rules.filter(function (r) { return vrr.indexOf(r.output) >= 0 }).map(D.nudged)
    _eval(D.script(nudges), function (ok, output) {
      if (!ok) {
        callback(false, output)
        return
      }
      // Hyprland activates rules on its next refresh; let the nudge land first.
      later.run(500, function () { root._eval(main, callback) })
    })
  }

  // Monitors that are on once the requested change is in place.
  function _enabledAfterApply() {
    return _snapshot.filter(function (m) {
      var want = D.find(root._requested, m.name)
      return want ? want.enabled : !m.disabled
    }).map(function (m) { return m.name })
  }

  function _restoreWorkspaces(enabledNames) {
    var script = D.workspaceScript(_snapshot, enabledNames)
    if (script) Quickshell.execDetached(["hyprctl", "eval", script])
  }

  function _eval(script, callback) {
    runner.run(["hyprctl", "eval", script], function (code, output) {
      var text = output.trim()
      var ok = code === 0 && text.indexOf("error") !== 0
      callback(ok, text.replace(/^error:\s*/, "").replace(/^\[string [^\]]*\]:\d+:\s*/, ""))
    })
  }

  // Hyprland reports VRR as active even when the driver refused it; the only
  // trace is a line in its log.
  function _checkVrrLog() {
    if (_logStart < 0) return
    logRunner.run(["sh", "-c", "tail -n +\"$2\" \"$1\" | grep -o 'Pending output [^ ]* does not accept VRR' | sort -u", "sh", _log, String(_logStart + 1)],
      function (code, output) {
        var refused = output.split("\n").map(function (l) {
          var m = /Pending output (\S+) does not accept VRR/.exec(l)
          return m ? m[1] : ""
        }).filter(function (n) { return n.length > 0 })
        if (!refused.length || root.state !== "confirming") return
        root.issues = root.issues.concat(refused.map(function (n) {
          return n + "'s driver refused VRR, although Hyprland reports it as on."
        }))
      })
  }

  Command {
    id: runner
  }

  Command {
    id: logRunner
  }

  Command {
    id: sdrRunner
  }

  Command {
    id: flagRunner
  }

  Timer {
    id: later
    property var fn: null
    function run(ms, f) {
      fn = f
      interval = ms
      restart()
    }
    onTriggered: {
      var f = fn
      fn = null
      if (f) f()
    }
  }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    onTriggered: {
      root.secondsLeft -= 1
      if (root.secondsLeft <= 0)
        root._revert("No answer within " + root.timeout + " s, so the previous settings were restored.", false)
    }
  }

  // Let Hyprland settle, put workspaces back, then compare with the request.
  Timer {
    id: settle
    interval: 700
    onTriggered: {
      Hypr.refresh()
      Globals.refresh()
      root._restoreWorkspaces(root._enabledAfterApply())
      verify.restart()
    }
  }

  Timer {
    id: verify
    interval: 900
    onTriggered: {
      var found = D.verify(root._requested, Hypr.monitors)
      Object.keys(root._globalsAfter).forEach(function (k) {
        if (Globals.values[k] !== root._globalsAfter[k])
          found.push("Hyprland kept " + G.option(k).label + " at " + G.label(k, Globals.values[k]) + ".")
      })
      root.issues = found
      root._checkVrrLog()
    }
  }

  Timer {
    id: quitDelay
    interval: 300
    onTriggered: {
      // As a plugin this singleton outlives the panel, so a quit must not
      // carry over into the next time a revert finishes.
      root._quitAfter = false
      root.readyToQuit()
    }
  }

  Connections {
    target: Hypr
    function onConfigReloaded() {
      root.appliedRules = ({})
      root.appliedGlobals = ({})
      root._sdrNext = ({})
      if (root._expectReload) {
        root._expectReload = false
        return
      }
      if (root.state === "confirming") {
        countdown.stop()
        root.state = "idle"
        root._say("Hyprland reloaded its config during the countdown, so your saved settings are back.", true)
      } else if (root.liveUnsaved) {
        root.liveUnsaved = false
        root._say("Hyprland reloaded its config; the unsaved live changes were replaced by your saved settings.", false)
      }
    }
  }
}
