pragma Singleton
import QtQuick
import Quickshell
import "../lib/draft.js" as D
import "../lib/layout.js" as L
import "../lib/scale.js" as S
import "../lib/globals.js" as G

// Pending edits layered over the current state. `edits` maps a connector name
// to the fields the user changed and `globalEdits` holds global options;
// everything else keeps following Hyprland, so hot-plug and outside changes
// show up immediately. Reset drops the edits.
Singleton {
  id: root

  property var edits: ({})
  property var globalEdits: ({})

  // What a monitor last asked for: a rule applied this session, else its saved
  // rule. Its color and VRR values are the base for editing (see lib/draft.js).
  function requestedFor(mon) {
    return Apply.appliedRules[mon.name] || Persist.savedRequestFor(mon) || null
  }

  readonly property var base: Hypr.monitors.map(function (m) { return D.fromLive(m, Hypr.monitors, root.requestedFor(m)) })
  readonly property var configs: base.map(function (b) { return D.merge(b, root.edits[b.name]) })
  // What Apply sends: positions shifted so the layout starts at 0,0.
  readonly property var pending: Object.keys(edits).length ? D.normalize(configs) : configs
  readonly property var changes: D.changes(base, pending)

  readonly property var globals: Object.assign({}, Globals.values, globalEdits)
  // Only the options that differ from their live value.
  readonly property var globalChanges: {
    var out = {}
    Object.keys(globalEdits).forEach(function (k) {
      if (globalEdits[k] !== Globals.values[k]) out[k] = globalEdits[k]
    })
    return out
  }
  readonly property var globalLines: G.describe(Globals.values, globalChanges)

  readonly property bool dirty: changes.length > 0 || globalLines.length > 0
  readonly property var errors: changes.length ? D.validate(pending) : []

  function config(name) { return D.find(configs, name) }
  function baseOf(name) { return D.find(base, name) }
  function isChanged(name) { return !!D.find(changes, name) }

  function set(name, fields) {
    var b = baseOf(name)
    if (!b) return
    var next = Object.assign({}, edits)
    var e = Object.assign({}, next[name] || {}, fields)
    // Fields back at their base value aren't edits any more.
    Object.keys(e).forEach(function (k) {
      if (D.sameField(k, e[k], b[k])) delete e[k]
    })
    if (Object.keys(e).length) next[name] = e
    else delete next[name]
    edits = next
  }

  function setGlobal(key, value) {
    var next = Object.assign({}, globalEdits)
    if (value === Globals.values[key]) delete next[key]
    else next[key] = value
    globalEdits = next
  }

  function reset() {
    edits = ({})
    globalEdits = ({})
  }

  function placedRects(except) {
    return configs.filter(function (c) { return D.isPlaced(c) && c.name !== except }).map(D.rect)
  }

  function move(name, x, y) {
    set(name, { x: Math.round(x), y: Math.round(y) })
  }

  function setEnabled(name, on) {
    var cfg = config(name)
    if (!cfg) return
    if (!on) {
      set(name, { enabled: false })
      return
    }
    var pos = L.autoPlace(D.rect(cfg), placedRects(name))
    set(name, { enabled: true, mirror: "", x: pos.x, y: pos.y })
  }

  function setMirror(name, target) {
    var cfg = config(name)
    if (!cfg) return
    if (target) {
      set(name, { mirror: target })
      return
    }
    var pos = L.autoPlace(D.rect(cfg), placedRects(name))
    set(name, { mirror: "", x: pos.x, y: pos.y })
  }

  // Size-changing edits keep neighbours to the right and below flush.
  function resize(name, fields) {
    var cfg = config(name)
    if (!cfg) return
    if (D.isPlaced(cfg)) {
      var after = D.rect(D.merge(cfg, fields))
      var rects = configs.filter(D.isPlaced).map(D.rect)
      L.resize(rects, name, after.width, after.height).forEach(function (r) {
        if (r.name !== name) root.move(r.name, r.x, r.y)
      })
    }
    set(name, fields)
  }

  // A new resolution keeps the scale when it's still clean for it, otherwise
  // takes the nearest clean one.
  function setMode(name, width, height, refresh) {
    var cfg = config(name)
    if (!cfg) return
    var scale = S.isValid(width, height, cfg.scale) ? cfg.scale : S.nearest(width, height, cfg.scale)
    resize(name, { width: width, height: height, refresh: refresh, scale: scale })
  }

  function setScale(name, scale) {
    resize(name, { scale: scale })
  }

  function setTransform(name, transform) {
    resize(name, { transform: transform })
  }

  // Color/VRR field from text (IPC): numbers and presets as Hyprland takes them.
  function setColorFromString(name, key, value) {
    if (D.COLOR.indexOf(key) < 0) return
    var fields = {}
    fields[key] = D.normalizeColor(key, value)
    set(name, fields)
  }

  function setGlobalFromString(key, value) {
    var opt = G.option(key)
    if (!opt) return
    setGlobal(key, opt.type === "bool" ? value === "true" || value === "1" : opt.type === "int" ? Number(value) : value)
  }
}
