pragma Singleton
import QtQuick
import Quickshell
import "../lib/brightness.js" as Br

// Monitor brightness through bin/panorama-brightness, the same backend the
// brightness keys use (on Omarchy: omarchy-brightness-display). It's polled,
// so the sliders follow the keys. Changes apply at once (no countdown); while
// a slider moves, the newest value wins and polls don't pull it back.
Singleton {
  id: root

  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../bin/panorama-brightness")).replace(/^file:\/\//, ""))

  // name → { backend: backlight|ddc|none, percent, available }
  property var values: ({})
  // name → { caps: { code: { name, values } }, vcp: { code: { value, max } } } for DDC/CI monitors
  property var features: ({})

  property var _pending: ({})
  property var _touched: ({})
  property bool _sending: false
  property var _vcpPending: ({})
  property bool _vcpSending: false

  function available(name) { var v = values[name]; return !!(v && v.available) }
  function percentOf(name) { var v = values[name]; return v && v.available ? v.percent : 0 }
  function backendOf(name) { var v = values[name]; return v ? v.backend : "" }

  function set(name, percent) {
    percent = Br.clampPercent(percent)
    _remember(name, { percent: percent })
    var p = Object.assign({}, _pending)
    p[name] = percent
    _pending = p
    _next()
  }

  function _remember(name, fields) {
    var v = Object.assign({}, values)
    if (v[name]) v[name] = Object.assign({}, v[name], fields)
    values = v
    var t = Object.assign({}, _touched)
    t[name] = Date.now()
    _touched = t
  }

  function _next() {
    if (_sending) return
    var names = Object.keys(_pending)
    if (!names.length) return
    var name = names[0], percent = _pending[name]
    var p = Object.assign({}, _pending)
    delete p[name]
    _pending = p
    _sending = true
    setter.run([helper, "set", name, percent + "%"], function () {
      root._sending = false
      root._next()
    })
  }

  function refresh() {
    if (poller.running) return
    poller.run([helper, "list"], function (code, output) {
      var fresh = Br.parseList(output)
      var now = Date.now()
      Object.keys(fresh).forEach(function (n) {
        // A value the user is still moving beats the poll.
        if (root._pending[n] !== undefined || now - (root._touched[n] || 0) < 1500)
          fresh[n] = Object.assign({}, fresh[n], { percent: root.values[n] ? root.values[n].percent : fresh[n].percent })
      })
      root.values = fresh
    })
  }

  // DDC/CI extras (contrast, input source, color preset): capabilities first,
  // then the current value of each feature shown.
  function loadFeatures(name) {
    if (backendOf(name) !== "ddc" || featureRunner.running) return
    featureRunner.run([helper, "caps", name], function (code, output) {
      var caps = Br.parseCaps(output)
      root._readVcps(name, caps, ["12", "14", "60"].filter(function (c) { return !!caps[c] }), {})
    })
  }

  function _readVcps(name, caps, codes, acc) {
    if (!codes.length) {
      var f = Object.assign({}, features)
      f[name] = { caps: caps, vcp: acc }
      features = f
      return
    }
    featureRunner.run([helper, "vcp", name, codes[0]], function (code, output) {
      acc[codes[0]] = Br.parseVcp(output)
      root._readVcps(name, caps, codes.slice(1), acc)
    })
  }

  function setVcp(name, code, value) {
    var f = features[name]
    if (f && f.vcp[code]) {
      var next = Object.assign({}, features)
      var vcp = Object.assign({}, f.vcp)
      vcp[code] = Object.assign({}, vcp[code], { value: value })
      next[name] = { caps: f.caps, vcp: vcp }
      features = next
    }
    var p = Object.assign({}, _vcpPending)
    p[name + ":" + code] = value
    _vcpPending = p
    _nextVcp()
  }

  function _nextVcp() {
    if (_vcpSending) return
    var keys = Object.keys(_vcpPending)
    if (!keys.length) return
    var key = keys[0], value = _vcpPending[key]
    var p = Object.assign({}, _vcpPending)
    delete p[key]
    _vcpPending = p
    _vcpSending = true
    var parts = key.split(":")
    vcpSetter.run([helper, "vcp", parts[0], parts[1], String(value)], function () {
      root._vcpSending = false
      root._nextVcp()
    })
  }

  Command { id: poller }
  Command { id: setter }
  Command { id: featureRunner }
  Command { id: vcpSetter }

  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
