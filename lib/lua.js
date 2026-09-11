.pragma library

// Lua source for `hyprctl eval`. Everything interpolated into Lua goes through
// here: strings are always quoted and escaped, numbers must be finite, and
// table keys must be plain identifiers, so a hostile monitor or workspace name
// can't break out of a string literal.

var IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]*$/;
var FUNCTION_PATH = /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$/;

function str(value) {
  var s = String(value);
  var out = "";
  for (var i = 0; i < s.length; i++) {
    var ch = s.charAt(i);
    var code = s.charCodeAt(i);
    if (ch === "\\") out += "\\\\";
    else if (ch === "\"") out += "\\\"";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    // Other control characters as three-digit decimal escapes, so a digit that
    // follows can't extend the escape.
    else if (code < 32 || code === 127) out += "\\" + ("00" + code).slice(-3);
    else out += ch;
  }
  return "\"" + out + "\"";
}

function num(value) {
  if (typeof value !== "number" || !isFinite(value)) throw new Error("Not a finite number: " + value);
  return String(Number(value.toFixed(6)));
}

function value(v) {
  if (typeof v === "string") return str(v);
  if (typeof v === "number") return num(v);
  if (typeof v === "boolean") return v ? "true" : "false";
  if (Array.isArray(v)) return v.length ? "{ " + v.map(value).join(", ") + " }" : "{}";
  if (v !== null && typeof v === "object") {
    var parts = [];
    Object.keys(v).forEach(function (key) {
      if (v[key] === undefined) return;
      if (!IDENTIFIER.test(key)) throw new Error("Not a Lua identifier: " + key);
      parts.push(key + " = " + value(v[key]));
    });
    return parts.length ? "{ " + parts.join(", ") + " }" : "{}";
  }
  throw new Error("Can't serialize " + v);
}

function call(fn, arg) {
  if (!FUNCTION_PATH.test(fn)) throw new Error("Not a function path: " + fn);
  return fn + "(" + value(arg) + ")";
}

function monitor(spec) {
  if (!spec || typeof spec.output !== "string") throw new Error("hl.monitor needs an output");
  return call("hl.monitor", spec);
}

// Reads back a single call with a table-literal argument, as written by
// `call`: `fn({ key = value, nested = { … }, ["dotted.key"] = … })`. Values
// may be strings, numbers, booleans or tables; anything else (variables,
// expressions) throws, so hand-written rules that use them are left alone.
function parseCall(text) {
  var s = String(text);
  var i = 0;

  function fail(what) { throw new Error("Can't read Lua at " + i + ": " + what); }
  function space() { while (i < s.length && /\s/.test(s[i])) i++; }
  function eat(ch) {
    space();
    if (s[i] !== ch) fail("expected " + ch);
    i++;
  }

  function string() {
    var quote = s[i++], out = "";
    while (i < s.length && s[i] !== quote) {
      if (s[i] === "\\") {
        i++;
        var digits = /^\d{1,3}/.exec(s.slice(i));
        if (digits) {
          out += String.fromCharCode(parseInt(digits[0], 10));
          i += digits[0].length;
        } else {
          out += { n: "\n", r: "\r", t: "\t" }[s[i]] || s[i];
          i++;
        }
      } else {
        out += s[i++];
      }
    }
    if (s[i] !== quote) fail("unterminated string");
    i++;
    return out;
  }

  function val() {
    space();
    var ch = s[i];
    if (ch === "{") return table();
    if (ch === "\"" || ch === "'") return string();
    var num = /^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?/.exec(s.slice(i));
    if (num) {
      i += num[0].length;
      return Number(num[0]);
    }
    if (s.slice(i, i + 4) === "true") { i += 4; return true; }
    if (s.slice(i, i + 5) === "false") { i += 5; return false; }
    fail("unsupported value");
  }

  function table() {
    eat("{");
    var obj = {}, list = [], keyed = false;
    for (;;) {
      space();
      if (s[i] === "}") { i++; break; }
      var key = null;
      var ident = /^[A-Za-z_][A-Za-z0-9_]*(?=\s*=)/.exec(s.slice(i));
      if (ident) {
        key = ident[0];
        i += key.length;
        eat("=");
      } else if (s[i] === "[") {
        i++;
        space();
        key = string();
        eat("]");
        eat("=");
      }
      var v = val();
      if (key === null) list.push(v);
      else {
        obj[key] = v;
        keyed = true;
      }
      space();
      if (s[i] === "," || s[i] === ";") i++;
      else if (s[i] !== "}") fail("expected , or }");
    }
    return keyed || !list.length ? obj : list;
  }

  space();
  var fn = /^[A-Za-z_][A-Za-z0-9_.]*/.exec(s.slice(i));
  if (!fn) fail("expected a function name");
  i += fn[0].length;
  eat("(");
  var args = [table()];
  space();
  while (s[i] === ",") {
    i++;
    space();
    args.push(table());
    space();
  }
  eat(")");
  return { fn: fn[0], arg: args[0], args: args };
}
