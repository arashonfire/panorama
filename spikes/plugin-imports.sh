#!/usr/bin/env bash
# Spike: can one QML tree serve both entry points -- Panorama standalone under
# `qs -p <root>`, and the same code loaded as an Omarchy shell plugin from
# ~/.config/omarchy/plugins/<id>/, outside that root?
#
# It matters because the two differ in how QML types resolve. Under `qs -p`,
# Quickshell roots `qs.` at the config directory and registers the singletons it
# finds there; a plugin gets neither -- the host shell owns `qs.`, and the
# plugin's own folder is just a path. So `import qs.services` from a plugin
# silently binds to the *host's* services, and `pragma Singleton` files without
# a qmldir quietly become one instance per import site.
#
# Builds a throwaway two-root harness (an app tree, and a fake host shell with
# decoy services/ and ui/ directories that win if resolution ever leaks) and
# asserts one case per behaviour, so a future Quickshell or Omarchy can be
# re-checked in one run. Nothing is shown on screen: every window is
# visible:false and each instance quits itself.
set -u

command -v qs >/dev/null || { echo "spike: Quickshell (qs) is not installed" >&2; exit 1; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/panorama-plugin-imports.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT"/app/services "$ROOT"/app/ui "$ROOT"/host/services "$ROOT"/host/ui

pass=0 fail=0

# ---------------------------------------------------------------- the app tree

# Two singletons, so both reference styles are covered: Peer reaches Svc as a
# bare sibling with no import at all -- exactly what services/Apply.qml does.
cat >"$ROOT/app/services/Svc.qml" <<'EOF'
pragma Singleton
import QtQuick
import Quickshell
Singleton {
  readonly property string who: "APP-SVC"
  property int counter: 0
  property Tool tool: Tool {}
  readonly property int toolV: tool.v
}
EOF

# A plain component sharing the services directory -- services/Command.qml's
# case. It is reached as a bare sibling from Svc, with no import.
cat >"$ROOT/app/services/Tool.qml" <<'EOF'
import QtQuick
QtObject { readonly property int v: 7 }
EOF

cat >"$ROOT/app/services/Peer.qml" <<'EOF'
pragma Singleton
import QtQuick
import Quickshell
Singleton {
  function bump() { Svc.counter = 42 }
}
EOF

# A component one level down, reaching back up -- the ui/*.qml case.
cat >"$ROOT/app/ui/Widget.qml" <<'EOF'
import QtQuick
import "../services"
Item {
  readonly property string host: Svc.who
  readonly property int seen: Svc.counter
}
EOF

# The shared component both entry points mount. Writes through "services",
# reads back through ui/Widget's "../services": if those two spellings yield
# two instances, shared=false.
cat >"$ROOT/app/Probe.qml" <<'EOF'
import QtQuick
import "services"
import "ui"
Item {
  Widget { id: w }
  Component.onCompleted: {
    var note = ""
    try { Peer.bump() } catch (e) { note = " bare-sibling-ref=THREW" }
    console.log("RESULT: shared=" + (w.seen === 42) + " host=" + (w.host || "<none>")
                + " tool=" + Svc.toolV + note)
  }
}
EOF

# Standalone entry, as bin/panorama launches it.
cat >"$ROOT/app/shell.qml" <<'EOF'
import QtQuick
import Quickshell
ShellRoot {
  Probe {}
  Timer { running: true; interval: 400; onTriggered: Qt.quit() }
}
EOF

# Plugin entry: the panel contract from shell/shell.qml -- a plain Item with
# open()/hide()/opened, no ShellRoot. Mounts Probe as a sibling type, with no
# explicit import "." , to check implicit same-directory resolution.
cat >"$ROOT/app/Panel.qml" <<'EOF'
import QtQuick
Item {
  property bool opened: false
  function open(payloadJson) { opened = true }
  function hide() { opened = false }
  Probe {}
}
EOF

# Today's import style, for the control case.
cat >"$ROOT/app/Legacy.qml" <<'EOF'
import QtQuick
import qs.services
Item {
  property bool opened: false
  function open(payloadJson) { opened = true }
  function hide() { opened = false }
  Component.onCompleted: console.log("RESULT: host=" + Svc.who)
}
EOF

# Panorama draws a FloatingWindow plus per-screen PanelWindows; both have to be
# constructible from plugin context. Never shown.
cat >"$ROOT/app/Windows.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Wayland
Item {
  property bool opened: false
  function open(payloadJson) { opened = true }
  function hide() { opened = false }
  FloatingWindow { id: fw; visible: false; title: "spike" }
  PanelWindow { id: pw; visible: false; WlrLayershell.layer: WlrLayer.Overlay }
  Component.onCompleted: console.log("RESULT: floating=" + (fw !== null) + " panel=" + (pw !== null))
}
EOF

# ------------------------------------------------------ the fake host shell

# Decoys: if `qs.` or a relative import ever resolved against the host root
# instead of the plugin's own folder, these are what the plugin would get.
cat >"$ROOT/host/services/Svc.qml" <<'EOF'
pragma Singleton
import QtQuick
import Quickshell
Singleton { readonly property string who: "HOST-DECOY"; property int counter: 0 }
EOF
printf 'singleton Svc 1.0 Svc.qml\n' >"$ROOT/host/services/qmldir"
cat >"$ROOT/host/ui/Widget.qml" <<'EOF'
import QtQuick
Item { readonly property string host: "HOST-DECOY"; readonly property int seen: -1 }
EOF

# Mirrors PluginRegistry.entryPointUrl -> Util.fileUrl: a Loader pointed at an
# absolute URL outside the host root. $SPIKE_URL is used verbatim so the spike
# can also show what a non-file:// path does.
cat >"$ROOT/host/shell.qml" <<'EOF'
import QtQuick
import Quickshell
ShellRoot {
  Loader {
    source: Quickshell.env("SPIKE_URL")
    onStatusChanged: if (status === Loader.Error) console.log("RESULT: LOAD ERROR")
  }
  Timer { running: true; interval: 600; onTriggered: Qt.quit() }
}
EOF

# ------------------------------------------------------------------- harness

qmldir_on() {
  printf 'singleton Svc 1.0 Svc.qml\nsingleton Peer 1.0 Peer.qml\nTool 1.0 Tool.qml\n' \
    >"$ROOT/app/services/qmldir"
}
qmldir_off() { rm -f "$ROOT/app/services/qmldir"; }
# The easy mistake: a qmldir that lists the singletons and forgets the plain
# component beside them.
qmldir_singletons_only() {
  printf 'singleton Svc 1.0 Svc.qml\nsingleton Peer 1.0 Peer.qml\n' >"$ROOT/app/services/qmldir"
}

# Runs one instance and echoes its RESULT payload (or a marker if none came).
standalone() {
  timeout 30 qs -n -p "$ROOT/app" 2>&1 | sed -n 's/.*RESULT: //p' | head -1
}
plugin() {
  SPIKE_URL="$1" timeout 30 qs -n -p "$ROOT/host" 2>&1 | sed -n 's/.*RESULT: //p' | head -1
}
# The innermost "caused by" line, for the cases whose point is that loading fails.
standalone_error() {
  timeout 30 qs -n -p "$ROOT/app" 2>&1 | sed -n 's/.*caused by @[^ ]*: //p' | tail -1
}

check() {
  local name=$1 expected=$2 got=$3
  if [[ $got == "$expected" ]]; then
    pass=$((pass + 1))
    printf '  ok   %-46s %s\n' "$name" "$got"
  else
    fail=$((fail + 1))
    printf '  FAIL %-46s got %-28s want %s\n' "$name" "${got:-<no RESULT>}" "$expected"
  fi
}

echo "## with services/qmldir -- the shape to ship"
qmldir_on
check "standalone, relative imports"      "shared=true host=APP-SVC tool=7" "$(standalone)"
check "plugin, relative imports"          "shared=true host=APP-SVC tool=7" "$(plugin "file://$ROOT/app/Panel.qml")"
check "plugin, window types"              "floating=true panel=true" "$(plugin "file://$ROOT/app/Windows.qml")"

# Panel.qml mounts Probe with no `import "."`; the cases above passing is the
# evidence that same-directory types resolve implicitly in both modes.

echo
echo "## without services/qmldir -- why the qmldir is load-bearing"
qmldir_off
# Under `qs -p` Quickshell registers the config root's singletons itself, which
# is why Panorama needs no qmldir today.
check "standalone, no qmldir (works today)" "shared=true host=APP-SVC tool=7" "$(standalone)"
# Outside that root nothing registers them: every import site gets its own
# instance and the bare sibling reference degrades, with no load error at all.
check "plugin, no qmldir (silent split)"  "shared=false host=<none> tool=undefined bare-sibling-ref=THREW" \
      "$(plugin "file://$ROOT/app/Panel.qml")"

echo
echo "## a qmldir that forgets a plain sibling -- breaks standalone only"
qmldir_singletons_only
# Once a qmldir exists it, not the directory listing, is what the `qs -p`
# engine resolves siblings through, so an omitted type is simply not a type.
check "standalone, sibling omitted from qmldir" "Tool is not a type" "$(standalone_error)"
# The plugin engine never gets that registration and keeps falling back to
# plain same-directory lookup -- which is why this failure looks like it only
# afflicts standalone, and why the spike has to assert both halves.
check "plugin, sibling omitted from qmldir" "shared=true host=APP-SVC tool=7" \
      "$(plugin "file://$ROOT/app/Panel.qml")"

echo
echo "## hazards this rules out"
qmldir_on
# `import qs.services` from a plugin resolves against the host shell, not the
# plugin folder -- no error, no warning, just the wrong singletons.
check "plugin, import qs.services"        "host=HOST-DECOY" "$(plugin "file://$ROOT/app/Legacy.qml")"
# A bare path gets rewritten to Quickshell's qs: scheme, and every relative
# import under it dies with "is not a type". Omarchy passes a file:// URL.
check "plugin mounted by bare path"       "LOAD ERROR" "$(plugin "$ROOT/app/Panel.qml")"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
