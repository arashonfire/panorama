.pragma library

// Arranging monitors in logical pixels. A rect is { name, x, y, width, height }.

function overlaps(a, b) {
  return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}

// Shares a stretch of edge (a corner alone doesn't count) without overlapping.
function touches(a, b) {
  if (overlaps(a, b)) return false;
  var spanX = a.x < b.x + b.width && b.x < a.x + a.width;
  var spanY = a.y < b.y + b.height && b.y < a.y + a.height;
  var edgeX = a.x + a.width === b.x || b.x + b.width === a.x;
  var edgeY = a.y + a.height === b.y || b.y + b.height === a.y;
  return (edgeX && spanY) || (edgeY && spanX);
}

function nearestWithin(value, candidates, threshold) {
  var best = value, bestDistance = threshold;
  candidates.forEach(function (c) {
    var d = Math.abs(c - value);
    if (d <= bestDistance) {
      best = c;
      bestDistance = d;
    }
  });
  return best;
}

// Pulls the rect's edges onto nearby edges of the others, per axis: flush
// against a side, or aligned with a top/bottom/left/right edge.
function snap(rect, others, threshold) {
  var xs = [], ys = [];
  others.forEach(function (o) {
    xs.push(o.x - rect.width, o.x + o.width, o.x, o.x + o.width - rect.width);
    ys.push(o.y - rect.height, o.y + o.height, o.y, o.y + o.height - rect.height);
  });
  return { x: nearestWithin(rect.x, xs, threshold), y: nearestWithin(rect.y, ys, threshold) };
}

// Where a dropped rect ends up: where it is if that touches another rect
// without overlapping any, otherwise the closest free spot flush against a
// side of one of them.
function settle(rect, others) {
  var r = { name: rect.name, x: Math.round(rect.x), y: Math.round(rect.y), width: rect.width, height: rect.height };
  if (!others.length) return { x: r.x, y: r.y };

  var free = function (x, y) {
    var candidate = { x: x, y: y, width: r.width, height: r.height };
    return !others.some(function (o) { return overlaps(candidate, o); });
  };
  if (free(r.x, r.y) && others.some(function (o) { return touches(r, o); })) return { x: r.x, y: r.y };

  var best = null, bestDistance = Infinity;
  others.forEach(function (o) {
    // Slide along the side as close to the drop point as possible while still
    // sharing a quarter of the shorter edge, so the cursor can actually cross.
    var shareY = Math.min(r.height, o.height) / 4;
    var shareX = Math.min(r.width, o.width) / 4;
    var alongY = Math.min(Math.max(r.y, o.y - r.height + shareY), o.y + o.height - shareY);
    var alongX = Math.min(Math.max(r.x, o.x - r.width + shareX), o.x + o.width - shareX);
    [[o.x - r.width, alongY], [o.x + o.width, alongY], [alongX, o.y - r.height], [alongX, o.y + o.height]].forEach(function (c) {
      if (!free(c[0], c[1])) return;
      var d = Math.hypot(c[0] - r.x, c[1] - r.y);
      if (d < bestDistance) {
        bestDistance = d;
        best = { x: Math.round(c[0]), y: Math.round(c[1]) };
      }
    });
  });
  return best || { x: r.x, y: r.y };
}

// Right of the rightmost rect, top-aligned with it.
function autoPlace(rect, others) {
  if (!others.length) return { x: 0, y: 0 };
  var right = others.reduce(function (a, o) { return o.x + o.width > a.x + a.width ? o : a; });
  return { x: Math.round(right.x + right.width), y: Math.round(right.y) };
}

// After `name` changes size, neighbours entirely to its right or below move by
// the size difference so side-by-side layouts stay flush. Returns new rects.
function resize(rects, name, width, height) {
  var old = null;
  rects.forEach(function (r) { if (r.name === name) old = r; });
  if (!old) return rects;
  var dw = width - old.width, dh = height - old.height;
  return rects.map(function (r) {
    if (r.name === name) return { name: r.name, x: r.x, y: r.y, width: width, height: height };
    var x = r.x >= old.x + old.width - 0.5 ? r.x + dw : r.x;
    var y = r.y >= old.y + old.height - 0.5 ? r.y + dh : r.y;
    return { name: r.name, x: Math.round(x), y: Math.round(y), width: r.width, height: r.height };
  });
}
