import QtQuick
import Quickshell.Io

// A one-shot process: `run(command, callback, input)` calls back with
// (exitCode, output) once the process has exited and its output is complete.
// stderr is folded into stdout, and `input`, when given, is written to stdin.
// The callback runs on a later tick, so it may start the next command.
Process {
  id: root

  property var _callback: null
  property string _input: ""
  property bool _useStdin: false
  property int _code: -1
  property bool _exited: false
  property bool _outDone: false

  function run(command, callback, input) {
    _callback = callback || null
    _useStdin = input !== undefined
    _input = _useStdin ? input : ""
    _code = -1
    _exited = false
    _outDone = false
    root.command = ["sh", "-c", "exec \"$@\" 2>&1", "sh"].concat(command)
    stdinEnabled = _useStdin
    running = true
  }

  function _finish() {
    if (!_exited || !_outDone || !_callback) return
    var cb = _callback
    var code = _code
    var text = output.text
    _callback = null
    Qt.callLater(function () { cb(code, text) })
  }

  onStarted: {
    if (!_useStdin) return
    write(_input)
    stdinEnabled = false
  }

  onExited: exitCode => {
    _code = exitCode
    _exited = true
    _finish()
  }

  stdout: StdioCollector {
    id: output
    onStreamFinished: {
      root._outDone = true
      root._finish()
    }
  }
}
