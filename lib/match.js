.pragma library

// How a saved rule picks its monitor, the way Hyprland does it: `desc:…` is a
// prefix of the monitor's description, anything else its connector name.

var INTERNAL_RE = /^(eDP|LVDS|DSI)-/;

function description(mon) {
  return String(mon.description || "").trim();
}

function selects(selector, mon) {
  if (String(selector).indexOf("desc:") === 0) {
    var want = selector.slice(5).trim();
    return want.length > 0 && description(mon).indexOf(want) === 0;
  }
  return selector === mon.name;
}

// A description only identifies a monitor if no other connected one starts with it.
function canMatchByMonitor(mon, monitors) {
  var desc = description(mon);
  return desc.length > 0 && !monitors.some(function (o) {
    return o.name !== mon.name && description(o).indexOf(desc) === 0;
  });
}

// "port" → the connector name; "monitor" → desc:<description>.
function selector(mon, how) {
  return how === "monitor" ? "desc:" + description(mon) : mon.name;
}

function isInternal(name) {
  return INTERNAL_RE.test(name);
}
