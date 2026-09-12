.pragma library
.import "lua.js" as Lua
.import "match.js" as Mt

// Profiles: a layout for one particular set of connected monitors, switched
// automatically. They live in Panorama's section of monitors.lua as one
// `panorama_profiles({ profiles }, { base rules })` call. The Lua function
// defined just above it (HANDLER) picks the profile whose monitors are exactly
// the connected ones, at load and whenever a monitor comes or goes, and applies
// its rules; with no match it re-applies the base rules. It only does so when
// the matching profile actually changed: turning a monitor off or on fires the
// same events, and re-applying the profile then would undo that change. Rules
// that turn the laptop panel off also set Omarchy's "laptop display off"
// toggle, and clear it again when the panel comes back (see claim/release).
//
// A profile: { name, monitors: [{ match, port }], rules: [rule tables],
// workspaces: [{ workspace, monitor }] }. `match` selects the monitor the way
// a rule does (connector or desc:…); `port` is the connector it was on, used
// for monitors that are connected but turned off, because Hyprland's Lua only
// lists enabled monitors (disabled ones are found in sysfs by connector).

var CALL = "panorama_profiles";

var HANDLER = [
  "-- Profiles: layouts for particular sets of connected monitors. The one that",
  "-- matches is applied at load and whenever a different one starts matching;",
  "-- with no match, the rules above. Written by Panorama.",
  "local function panorama_profiles(profiles, base, opts)",
  "  local function selects(sel, m)",
  "    if sel:sub(1, 5) == \"desc:\" then",
  "      local want = sel:sub(6):match(\"^%s*(.-)%s*$\")",
  "      return want ~= \"\" and (m.description or \"\"):sub(1, #want) == want",
  "    end",
  "    return m.name == sel",
  "  end",
  "  local function internal(name)",
  "    return name:match(\"^eDP%-\") or name:match(\"^LVDS%-\") or name:match(\"^DSI%-\")",
  "  end",
  "  -- Every DRM connector the kernel knows, and which of them are plugged in. A",
  "  -- virtual output (hyprctl output create) has no connector at all, so unknown",
  "  -- is not the same as unplugged.",
  "  local function drm()",
  "    local known, plugged = {}, {}",
  "    local h = io.popen(\"for f in /sys/class/drm/card*-*/status; do read -r s < \\\"$f\\\"; c=${f%/status}; c=${c##*/}; echo \\\"${c#card*-} $s\\\"; done 2>/dev/null\")",
  "    if h then",
  "      for line in h:lines() do",
  "        local name, status = line:match(\"^(%S+) (%S+)$\")",
  "        if name then",
  "          known[name] = true",
  "          if status == \"connected\" then plugged[name] = true end",
  "        end",
  "      end",
  "      h:close()",
  "    end",
  "    return known, plugged",
  "  end",
  "  -- Enabled monitors come from Hyprland; connected but disabled ones only from",
  "  -- sysfs. A port the kernel no longer reports is left out even when Hyprland",
  "  -- has not finished dropping it, so an unplug is never read as a display that",
  "  -- is still showing something.",
  "  local function connected()",
  "    local known, plugged = drm()",
  "    local list, seen = {}, {}",
  "    for _, m in ipairs(hl.get_monitors()) do",
  "      if plugged[m.name] or not known[m.name] then",
  "        list[#list + 1] = { name = m.name, description = m.description, enabled = true, virtual = not known[m.name] }",
  "        seen[m.name] = true",
  "      end",
  "    end",
  "    for name in pairs(plugged) do",
  "      if not seen[name] then list[#list + 1] = { name = name, enabled = false } end",
  "    end",
  "    return list",
  "  end",
  "  local function matches(profile, list)",
  "    if #profile.monitors ~= #list then return false end",
  "    local used = {}",
  "    for _, want in ipairs(profile.monitors) do",
  "      local found = false",
  "      for i, m in ipairs(list) do",
  "        if not used[i] and ((m.enabled and selects(want.match, m)) or (not m.enabled and m.name == want.port)) then",
  "          used[i] = true",
  "          found = true",
  "          break",
  "        end",
  "      end",
  "      if not found then return false end",
  "    end",
  "    return true",
  "  end",
  "  -- Omarchy's toggle flags: its own directory, unless one is given (tests).",
  "  -- Only written on Omarchy, recognised by its state directory.",
  "  local toggles = opts and opts.toggles",
  "  local omarchy = toggles ~= nil",
  "  if not toggles then",
  "    local state = (os.getenv(\"HOME\") or \"\") .. \"/.local/state/omarchy\"",
  "    omarchy = os.rename(state, state) and true or false",
  "    toggles = state .. \"/toggles/hypr\"",
  "  end",
  "  local DISABLE, CLAMSHELL = \"internal-monitor-disable.lua\", \"internal-monitor-clamshell.lua\"",
  "  local function toggle_path(name)",
  "    return toggles .. \"/\" .. name",
  "  end",
  "  local function toggle(name)",
  "    local f = io.open(toggle_path(name))",
  "    if f then f:close() return true end",
  "    return false",
  "  end",
  "  -- Omarchy owns the laptop panel while its clamshell mode (lid shut with an",
  "  -- external monitor) or its \"laptop display off\" toggle is set, so rules that",
  "  -- would turn the panel on must not fight it. Only while another display is",
  "  -- actually showing something, though: Omarchy's own paths check that too,",
  "  -- and with the external gone the panel is all that is left, so honouring",
  "  -- the toggle would leave the session with no screen.",
  "  local function external_on(list)",
  "    for _, m in ipairs(list) do",
  "      if m.enabled and not internal(m.name) then return true end",
  "    end",
  "    return false",
  "  end",
  "  local function internal_claimed(list)",
  "    if not external_on(list) then return false end",
  "    return toggle(CLAMSHELL) or toggle(DISABLE)",
  "  end",
  "  -- Whether the toggle stands for these rules (a profile that turns the panel",
  "  -- off) rather than for the user, through Omarchy's hotkey or Panorama.",
  "  local ours = false",
  "  -- Rules that turn the panel off need the toggle as well: Omarchy's watcher",
  "  -- re-enables an unflagged panel within seconds while a laptop is docked, and",
  "  -- its toggle directory loads after this file, so the next reload would also",
  "  -- put the panel back. Exactly the bytes Omarchy writes; nothing off Omarchy.",
  "  local function claim(name)",
  "    ours = true",
  "    if not omarchy or toggle(DISABLE) then return end",
  "    if not name:match(\"^[A-Za-z0-9._-]+$\") or toggles:find(\"[\\\"'\\\\]\") then return end",
  "    os.execute(\"mkdir -p \\\"\" .. toggles .. \"\\\"\")",
  "    local f = io.open(toggle_path(DISABLE), \"w\")",
  "    if f then f:write(\"hl.monitor({ output = \\\"\" .. name .. \"\\\", disabled = true })\\n\") f:close() end",
  "  end",
  "  local function release()",
  "    ours = false",
  "    if toggle(DISABLE) then pcall(os.remove, toggle_path(DISABLE)) end",
  "  end",
  "  -- The toggle only means anything while another display is showing",
  "  -- something, so once the external is gone it is cleared rather than left to",
  "  -- strand the session with no screen on the next reload. Omarchy's own",
  "  -- watcher clears it for the same reason; this does not wait for it.",
  "  local function release_claim(list)",
  "    if external_on(list) then return end",
  "    release()",
  "  end",
  "  -- The connected monitor a rule applies to, if any: by selector for the ones",
  "  -- Hyprland lists, by port for the ones only sysfs knows, as matches does.",
  "  local function rule_targets(rule, list)",
  "    for _, m in ipairs(list) do",
  "      if (m.enabled and selects(rule.output, m)) or (not m.enabled and rule.output == m.name) then return m end",
  "    end",
  "    return nil",
  "  end",
  "  local function targets_internal(rule, list)",
  "    if internal(rule.output) then return true end",
  "    for _, m in ipairs(list) do",
  "      if m.enabled and internal(m.name) and selects(rule.output, m) then return true end",
  "    end",
  "    return false",
  "  end",
  "  -- Whether a display other than the panel is on once `rules` are in force:",
  "  -- as the rules say for the displays they target, as it is for the rest.",
  "  local function external_after(rules, list)",
  "    local wanted = {}",
  "    for _, rule in ipairs(rules) do",
  "      local m = rule_targets(rule, list)",
  "      if m then wanted[m.name] = not rule.disabled end",
  "    end",
  "    for _, m in ipairs(list) do",
  "      if not internal(m.name) then",
  "        local on = wanted[m.name]",
  "        if on == nil then on = m.enabled end",
  "        if on then return true end",
  "      end",
  "    end",
  "    return false",
  "  end",
  "  -- Which profile is in force. Only a change is worth re-applying: turning a",
  "  -- monitor off or on (Panorama, Omarchy) also fires these events, but leaves",
  "  -- it connected, so the same profile still matches; re-applying it then would",
  "  -- undo the very change that fired the event. Applying rules fires them too,",
  "  -- and should that ever bring the previous profile straight back, the two",
  "  -- would alternate without end and take the compositor with them: the same",
  "  -- switch is not made twice within a second.",
  "  local NONE = {}",
  "  local last, ran, before, flipped = nil, false, NONE, -1",
  "  local function apply()",
  "    local list = connected()",
  "    local chosen = nil",
  "    for _, p in ipairs(profiles) do",
  "      if matches(p, list) then chosen = p break end",
  "    end",
  "    release_claim(list)",
  "    if ran and chosen == last then return end",
  "    if ran and (chosen or base) == before and os.time() == flipped then return end",
  "    before, flipped = ran and (last or base) or NONE, os.time()",
  "    ran, last = true, chosen",
  "    local rules = chosen and chosen.rules or base",
  "    -- What these rules say about the laptop panel: the connector they turn",
  "    -- off, or that they turn it on.",
  "    local panel_off, panel_on = nil, false",
  "    for _, rule in ipairs(rules) do",
  "      local m = rule_targets(rule, list)",
  "      if m and internal(m.name) then",
  "        if rule.disabled then panel_off = m.name else panel_on = true end",
  "      end",
  "    end",
  "    local claimed = internal_claimed(list)",
  "    if panel_off and external_after(rules, list) then",
  "      claim(panel_off)",
  "      claimed = false",
  "    elseif panel_on and claimed and ours then",
  "      release()",
  "      claimed = internal_claimed(list)",
  "    end",
  "    -- A virtual output (no connector) that is turned off vanishes from every",
  "    -- list there is, so it would read as unplugged, the profile would stop",
  "    -- matching and the rules turning it back on would apply: it stays on.",
  "    local off = {}",
  "    for _, rule in ipairs(rules) do",
  "      local m = rule_targets(rule, list)",
  "      if not (claimed and targets_internal(rule, list)) and not (rule.disabled and m and m.virtual) then",
  "        hl.monitor(rule)",
  "        if m then off[m.name] = rule.disabled and true or false end",
  "      end",
  "    end",
  "    -- Rules that would leave every connected display off would end the session",
  "    -- with no screen and no way to get one back, so the displays win over the",
  "    -- rules. A display turned off on purpose is only off while another shows.",
  "    local blank = true",
  "    for _, m in ipairs(list) do",
  "      if not off[m.name] then blank = false break end",
  "    end",
  "    if blank then",
  "      for _, m in ipairs(list) do",
  "        hl.monitor({ output = m.name, disabled = false, mode = \"preferred\", position = \"auto\", scale = \"auto\" })",
  "      end",
  "    end",
  "    for _, w in ipairs(chosen and chosen.workspaces or {}) do",
  "      hl.workspace_rule({ workspace = w.workspace, monitor = w.monitor, default = true })",
  "    end",
  "  end",
  "  hl.on(\"monitor.added\", apply)",
  "  hl.on(\"monitor.removed\", apply)",
  "  apply()",
  "end"
];

function identity(mon, how) {
  return { match: Mt.selector(mon, how), port: mon.name };
}

// Exactly this set of monitors (hyprctl objects, enabled and disabled)?
// Enabled monitors match by selector, disabled ones by port, like the Lua.
function matches(profile, monitors) {
  if (!profile || !profile.monitors || profile.monitors.length !== monitors.length) return false;
  var used = [];
  return profile.monitors.every(function (want) {
    for (var i = 0; i < monitors.length; i++) {
      if (used[i]) continue;
      var m = monitors[i];
      if (m.disabled ? m.name === want.port : Mt.selects(want.match, m)) {
        used[i] = true;
        return true;
      }
    }
    return false;
  });
}

function active(profiles, monitors) {
  for (var i = 0; i < (profiles || []).length; i++) {
    if (matches(profiles[i], monitors)) return profiles[i];
  }
  return null;
}

// The profile's rule for a monitor: through its entry in `monitors`, so it
// works for disabled monitors too.
function ruleFor(profile, mon) {
  if (!profile) return null;
  var entry = null;
  profile.monitors.forEach(function (w) {
    if (mon.disabled ? w.port === mon.name : Mt.selects(w.match, mon)) entry = w;
  });
  if (!entry) return null;
  var found = null;
  profile.rules.forEach(function (r) { if (r.output === entry.match) found = r; });
  return found;
}

// A profile for the connected `monitors`: `ruleOf(mon)` gives each monitor's
// rule table, `howOf(mon)` how it's matched ("port"/"monitor"). Keeps an
// existing profile's name and workspaces when `from` is given.
function capture(name, monitors, ruleOf, howOf, from) {
  return {
    name: from ? from.name : name,
    monitors: monitors.map(function (m) { return identity(m, howOf(m)); }),
    rules: monitors.map(function (m) {
      var r = {};
      var rule = ruleOf(m);
      Object.keys(rule).forEach(function (k) { r[k] = rule[k]; });
      r.output = Mt.selector(m, howOf(m));
      return r;
    }),
    workspaces: from ? (from.workspaces || []).slice() : []
  };
}

// "1, 2,5" → workspace entries for one monitor, replacing its old ones.
// Workspaces are numbers or name:/special: workspaces; anything else is dropped.
function setWorkspaces(profile, match, text) {
  var ids = String(text || "").split(/[\s,;]+/).filter(function (s) {
    return /^(\d+|(name|special):[A-Za-z0-9_.-]+)$/.test(s);
  });
  var others = (profile.workspaces || []).filter(function (w) {
    return w.monitor !== match && ids.indexOf(w.workspace) < 0;
  });
  var out = {};
  Object.keys(profile).forEach(function (k) { out[k] = profile[k]; });
  out.workspaces = others.concat(ids.map(function (id) { return { workspace: id, monitor: match }; }));
  return out;
}

function workspacesOf(profile, match) {
  return (profile.workspaces || []).filter(function (w) { return w.monitor === match; }).map(function (w) { return w.workspace; });
}

// Section lines: the handler, then the call with the profiles and base rules.
// `opts` (tests only) becomes the call's third argument, e.g. { toggles: dir }.
function render(profiles, base, opts) {
  if (!profiles || !profiles.length) return [];
  var lines = HANDLER.slice();
  lines.push(CALL + "({");
  profiles.forEach(function (p) {
    lines.push("  {");
    lines.push("    name = " + Lua.str(p.name) + ",");
    lines.push("    monitors = " + Lua.value(p.monitors) + ",");
    lines.push("    rules = {");
    p.rules.forEach(function (r) { lines.push("      " + Lua.value(r) + ","); });
    lines.push("    },");
    lines.push("    workspaces = " + Lua.value(p.workspaces || []) + ",");
    lines.push("  },");
  });
  lines.push("}, {");
  (base || []).forEach(function (r) { lines.push("  " + Lua.value(r) + ","); });
  if (opts) {
    lines.push("}, {");
    Object.keys(opts).forEach(function (k) { lines.push("  " + k + " = " + Lua.value(opts[k]) + ","); });
  }
  lines.push("})");
  return lines;
}

// Reads the call back from a section's lines: { profiles, base, start, end }
// (line indices), or null without one. Throws on a call it can't read.
function parse(lines) {
  var start = -1, end = -1;
  for (var i = 0; i < lines.length; i++) {
    if (start < 0 && new RegExp("^\\s*" + CALL + "\\(\\{\\s*$").test(lines[i])) start = i;
    else if (start >= 0 && /^\s*\}\)\s*$/.test(lines[i])) { end = i; break; }
  }
  if (start < 0 || end < 0) return null;
  var call = Lua.parseCall(lines.slice(start, end + 1).join("\n"));
  // Lua can't tell an empty list from an empty table; parseCall reads it as {}.
  var list = function (v) { return Array.isArray(v) ? v : []; };
  var profiles = list(call.args[0]).map(function (p) {
    return { name: String(p.name || "Profile"), monitors: list(p.monitors), rules: list(p.rules), workspaces: list(p.workspaces) };
  });
  return { profiles: profiles, base: list(call.args[1]), start: start, end: end };
}
