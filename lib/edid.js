.pragma library

// What a panel advertises, read from `edid-decode` output. Hyprland parses the
// EDID itself (libdisplay-info) and can miss things, e.g. HDR metadata inside
// a DisplayID extension, so this is shown next to what Hyprland actually does.

function num(re, text) {
  var m = re.exec(text);
  return m ? Number(m[1]) : null;
}

function all(re, text) {
  var out = [], m;
  var g = new RegExp(re.source, "g");
  while ((m = g.exec(text))) out.push(Number(m[1]));
  return out;
}

function parse(text) {
  var t = String(text || "");
  if (!/Block 0, Base EDID/.test(t)) return null;

  // HDR: CTA HDR Static Metadata (possibly inside DisplayID), or DisplayID's
  // supported color space / EOTF combinations.
  var staticBlock = /HDR Static Metadata Data Block:([\s\S]*?)(?:\n  \S|\nBlock |\n\S|$)/.exec(t);
  var staticText = staticBlock ? staticBlock[1] : "";
  var pq = /SMPTE ST2084/.test(staticText) || /SMPTE ST 2084/.test(t);
  var hlg = /Hybrid Log-Gamma|\bHLG\b/.test(staticText);

  // Content luminance the panel asks for; fall back to DisplayID's native values.
  var maxLum = num(/Desired content max luminance: \d+ \(([\d.]+) cd\/m\^2\)/, t);
  var avgLum = num(/Desired content max frame-average luminance: \d+ \(([\d.]+) cd\/m\^2\)/, t);
  var minLum = num(/Desired content min luminance: \d+ \(([\d.]+) cd\/m\^2\)/, t);
  if (maxLum === null) maxLum = num(/Native Maximum Luminance \(10% Rectangular Coverage\): ([\d.]+)/, t);
  if (avgLum === null) avgLum = num(/Native Maximum Luminance \(Full Coverage\): ([\d.]+)/, t);
  if (minLum === null) minLum = num(/Native Minimum Luminance: ([\d.]+)/, t);

  // Variable refresh: union of Adaptive Sync ranges, else vendor/range limits.
  var mins = all(/Min Refresh Rate: (\d+) Hz/, t).concat(all(/Minimum Refresh Rate: (\d+) Hz/, t));
  var maxs = all(/Max Refresh Rate: (\d+) Hz/, t).concat(all(/Maximum Refresh Rate: (\d+) Hz/, t));
  var range = /Monitor ranges \([^)]*\): (\d+)-(\d+) Hz V/.exec(t);
  var vrr = null;
  if (mins.length && maxs.length) vrr = { min: Math.min.apply(null, mins), max: Math.max.apply(null, maxs) };
  else if (range) vrr = { min: Number(range[1]), max: Number(range[2]) };

  // Deepest color the panel takes: the base block's bits per channel (often 8
  // or undefined on HDMI), HDMI deep color, or DisplayID's bpc lists.
  var bpcs = all(/Bits per primary color channel: (\d+)/, t).concat(all(/Native Color Depth: (\d+) bpc/, t));
  var lists = t.match(/Supported bpc for \S+ encoding: [\d, ]+/g) || [];
  lists.forEach(function (l) { bpcs = bpcs.concat(all(/(\d+)/, l.replace(/^[^:]*:/, ""))); });
  if (/\bDC_36bit\b|Supports 12-bits\/component Deep Color/.test(t)) bpcs.push(12);
  if (/\bDC_30bit\b|Supports 10-bits\/component Deep Color/.test(t)) bpcs.push(10);

  var name = /Display Product Name: '([^']*)'/.exec(t);
  var serial = /Display Product Serial Number: '([^']*)'/.exec(t);
  var size = /Maximum image size: (\d+) cm x (\d+) cm/.exec(t);

  return {
    manufacturer: (/Manufacturer: (\S+)/.exec(t) || [])[1] || "",
    productName: name ? name[1].trim() : "",
    serial: serial ? serial[1].trim() : "",
    year: num(/Made in: (?:week \d+ of )?(\d{4})/, t),
    sizeCm: size ? { width: Number(size[1]), height: Number(size[2]) } : null,
    bitsPerChannel: num(/Bits per primary color channel: (\d+)/, t),
    maxBpc: bpcs.length ? Math.max.apply(null, bpcs) : null,
    hdr: { pq: pq, hlg: hlg },
    bt2020: /BT2020(RGB|YCC)|BT\.2020/.test(t),
    dciP3: /DCI-P3/.test(t),
    luminance: { max: maxLum, maxAverage: avgLum, min: minLum },
    vrr: vrr
  };
}

// Short human summary, e.g. "HDR10 · 1107 nits peak · BT.2020 · 10-bit · VRR 49–165 Hz".
function summary(e) {
  if (!e) return "";
  var parts = [];
  if (e.hdr.pq) parts.push(e.hdr.hlg ? "HDR10 + HLG" : "HDR10");
  if (e.luminance.max) parts.push(Math.round(e.luminance.max) + " nits peak");
  if (e.bt2020) parts.push("BT.2020");
  else if (e.dciP3) parts.push("DCI-P3");
  if (e.bitsPerChannel) parts.push(e.bitsPerChannel + "-bit");
  if (e.vrr) parts.push("VRR " + e.vrr.min + "–" + e.vrr.max + " Hz");
  return parts.join(" · ");
}

// Whether the panel can do HDR and 10-bit: true, false, or null when there's no
// EDID to tell. HDR is HDR10 (PQ), the only kind Hyprland drives, and implies
// 10-bit; a panel that doesn't state its bit depth isn't ruled out.
function supports(e) {
  if (!e) return { hdr: null, tenBit: null };
  return {
    hdr: e.hdr.pq,
    tenBit: e.hdr.pq ? true : e.maxBpc === null ? null : e.maxBpc >= 10
  };
}

// Values for Hyprland's luminance overrides (nits; max ones are integers).
function luminanceOverrides(e) {
  if (!e) return null;
  var l = e.luminance;
  return {
    min_luminance: l.min !== null ? l.min : -1,
    max_luminance: l.max !== null ? Math.round(l.max) : -1,
    max_avg_luminance: l.maxAverage !== null ? Math.round(l.maxAverage) : -1
  };
}
