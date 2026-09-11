const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const load = require("./load");

const P = load("lib/profiles.js");
const plain = (v) => JSON.parse(JSON.stringify(v));
const [edp] = require("./fixtures/monitors-edp.json");

const dell = { ...edp, id: 1, name: "DP-2", description: "Dell Inc. DELL U2723QE ABC123", x: 1600, y: 0, scale: 1.5, focused: false };
const how = (m) => (m.name === "eDP-1" ? "port" : "monitor");
const rule = (m) => ({ output: m.name, disabled: false, mode: `${m.width}x${m.height}@60`, position: `${m.x}x${m.y}`, scale: m.scale });

const docked = P.capture("Desk", [edp, dell], rule, how);
const DOCKED = {
  name: "Desk",
  monitors: [{ match: "eDP-1", port: "eDP-1" }, { match: "desc:Dell Inc. DELL U2723QE ABC123", port: "DP-2" }],
  rules: [
    { output: "eDP-1", disabled: false, mode: "2560x1600@60", position: "0x0", scale: 1.6 },
    { output: "desc:Dell Inc. DELL U2723QE ABC123", disabled: false, mode: "2560x1600@60", position: "1600x0", scale: 1.5 }
  ],
  workspaces: []
};

test("capture records how each monitor is matched and where it was", () => {
  assert.deepEqual(plain(docked), DOCKED);
});

test("matches: exactly this set, enabled by selector, disabled by port", () => {
  assert.equal(P.matches(docked, [edp, dell]), true);
  assert.equal(P.matches(docked, [dell, edp]), true, "order doesn't matter");
  assert.equal(P.matches(docked, [edp]), false, "a subset isn't a match");
  assert.equal(P.matches(docked, [edp, dell, { ...dell, name: "DP-3", description: "Other" }]), false);
  assert.equal(P.matches(docked, [edp, { ...dell, name: "DP-1" }]), true, "desc: follows the monitor to another port");
  assert.equal(P.matches(docked, [{ ...edp, disabled: true }, dell]), true, "a turned-off panel still counts, by port");
  assert.equal(P.matches(docked, [edp, { ...dell, disabled: true, name: "DP-1" }]), false, "turned off and moved: can't tell");
  assert.equal(P.active([docked], [edp]), null);
  assert.equal(P.active([docked], [edp, dell]).name, "Desk");
});

test("ruleFor finds a monitor's rule, also when it's off", () => {
  assert.equal(P.ruleFor(docked, dell).position, "1600x0");
  assert.equal(P.ruleFor(docked, { ...edp, disabled: true }).output, "eDP-1");
  assert.equal(P.ruleFor(docked, { ...dell, name: "HDMI-A-1", description: "Nope" }), null);
});

test("workspaces per monitor", () => {
  let p = P.setWorkspaces(docked, "desc:Dell Inc. DELL U2723QE ABC123", "1, 2,3");
  p = P.setWorkspaces(p, "eDP-1", "4 5 2");
  assert.deepEqual(plain(P.workspacesOf(p, "desc:Dell Inc. DELL U2723QE ABC123")), ["1", "3"], "2 moved to eDP-1");
  assert.deepEqual(plain(P.workspacesOf(p, "eDP-1")), ["4", "5", "2"]);
  assert.deepEqual(plain(P.setWorkspaces(p, "eDP-1", "").workspaces).map((w) => w.workspace), ["1", "3"]);
  assert.deepEqual(plain(P.setWorkspaces(docked, "eDP-1", "1; rm -rf").workspaces), [{ workspace: "1", monitor: "eDP-1" }], "junk dropped");
  assert.deepEqual(plain(P.capture("x", [edp, dell], rule, how, p)).workspaces, plain(p.workspaces), "updating keeps workspaces");
});

test("render and parse round-trip", () => {
  const withWs = P.setWorkspaces(docked, "eDP-1", "1 2");
  const base = [{ output: "eDP-1", disabled: false, scale: 1.6 }];
  const lines = P.render([withWs, { ...docked, name: 'Couch "TV"' }], base);
  assert.equal(lines[0], P.HANDLER[0]);
  const parsed = plain(P.parse(["-- before", ...lines, "-- after"]));
  assert.deepEqual(parsed.profiles, plain([withWs, { ...docked, name: 'Couch "TV"' }]));
  assert.deepEqual(parsed.base, base);
  assert.equal(parsed.start, 1 + P.HANDLER.length);
  assert.equal(parsed.end, lines.length);
  assert.deepEqual(plain(P.render([], base)), []);
  assert.equal(P.parse(["hl.monitor({ output = \"x\" })"]), null);
});

// Run the generated Lua for real, with a stub `hl`, fake sysfs and fake HOME.
const lua = ["lua", "lua5.4", "luajit"].find((bin) => spawnSync(bin, ["-v"]).status === 0);
function runHandler({ enabled, connected, lidClosed, profiles, base, event }) {
  const stub = `
    local applied, ws, handlers = {}, {}, {}
    local enabled = { ${enabled.map((m) => `{ name = ${JSON.stringify(m.name)}, description = ${JSON.stringify(m.description || "")} }`).join(", ")} }
    hl = {
      get_monitors = function() return enabled end,
      monitor = function(r) applied[#applied + 1] = r.output .. (r.disabled and "(off)" or "") end,
      workspace_rule = function(w) ws[#ws + 1] = w.workspace .. "@" .. w.monitor end,
      on = function(name, fn) handlers[name] = fn end,
    }
    io.popen = function() local lines = { ${connected.map((c) => JSON.stringify(c)).join(", ")} } local i = 0
      return { lines = function() return function() i = i + 1 return lines[i] end end, close = function() end } end
    local real_open = io.open
    io.open = function(path) if path:match("clamshell") then return ${lidClosed ? "{ close = function() end }" : "nil"} end return real_open(path) end
    os.getenv = function() return "/home/test" end
  `;
  const body = P.render(profiles, base).join("\n");
  const after = `
    ${event ? `applied = {} handlers[${JSON.stringify(event)}]()` : ""}
    io.write(table.concat(applied, ",") .. "|" .. table.concat(ws, ",") .. "|" .. (handlers["monitor.added"] and "on" or "off"))
  `;
  const out = spawnSync(lua, ["-"], { input: stub + body + after, encoding: "utf8" });
  assert.equal(out.status, 0, out.stderr);
  return out.stdout;
}

test("generated Lua picks the matching profile, else the base rules", { skip: !lua && "no lua interpreter" }, () => {
  const off = { ...docked, name: "Docked, lid shut", rules: [{ output: "eDP-1", disabled: true }, DOCKED.rules[1]] };
  const base = [{ output: "eDP-1", disabled: false }];
  const withWs = P.setWorkspaces(docked, "desc:Dell Inc. DELL U2723QE ABC123", "1 2");
  const both = [{ name: "eDP-1" }, { name: "DP-2", description: dell.description }];

  assert.equal(runHandler({ enabled: both, connected: ["eDP-1", "DP-2"], profiles: [withWs], base }),
    "eDP-1,desc:Dell Inc. DELL U2723QE ABC123|1@desc:Dell Inc. DELL U2723QE ABC123,2@desc:Dell Inc. DELL U2723QE ABC123|on");
  assert.equal(runHandler({ enabled: [{ name: "eDP-1" }], connected: ["eDP-1"], profiles: [withWs], base }), "eDP-1||on", "no match: base");
  // The panel was turned off by the profile: Lua only sees it in sysfs.
  assert.equal(runHandler({ enabled: [{ name: "DP-2", description: dell.description }], connected: ["eDP-1", "DP-2"], profiles: [off], base }),
    "eDP-1(off),desc:Dell Inc. DELL U2723QE ABC123||on");
  // At startup nothing is enabled yet, but sysfs already knows what's plugged in.
  assert.equal(runHandler({ enabled: [], connected: ["eDP-1", "DP-2"], profiles: [docked], base }),
    "eDP-1,desc:Dell Inc. DELL U2723QE ABC123||on");
  // Lid closed: Omarchy's clamshell mode decides about the panel.
  assert.equal(runHandler({ enabled: both, connected: ["eDP-1", "DP-2"], lidClosed: true, profiles: [docked], base }),
    "desc:Dell Inc. DELL U2723QE ABC123||on");
  // Hot-plug event re-runs the choice.
  assert.equal(runHandler({ enabled: both, connected: ["eDP-1", "DP-2"], profiles: [docked], base, event: "monitor.removed" }),
    "eDP-1,desc:Dell Inc. DELL U2723QE ABC123||on");
});

test("generated Lua is valid", { skip: spawnSync("luac", ["-v"]).status !== 0 && "no luac" }, () => {
  const out = spawnSync("luac", ["-p", "-"], { input: P.render([docked], []).join("\n"), encoding: "utf8" });
  assert.equal(out.status, 0, out.stderr);
});
