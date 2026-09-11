import QtQuick
import qs.services
import "../lib/monitor.js" as M
import "../lib/draft.js" as D
import "../lib/layout.js" as L

// Scaled picture of the draft layout in logical pixels. Tiles can be dragged:
// edges snap to neighbours while moving, and on release the monitor settles
// flush against the nearest one without overlapping. Monitors that are off
// or mirroring sit in a tray along the bottom.
Rectangle {
  id: root

  property string selectedName
  signal select(string name)

  readonly property var configs: Draft.configs
  readonly property var placed: configs.filter(D.isPlaced)
  readonly property var others: configs.filter(function (c) { return !D.isPlaced(c) })
  readonly property var layoutBounds: M.bounds(placed.map(D.rect))
  readonly property var fitted: M.fit(layoutBounds, stage.width, stage.height, Math.round(40 * Theme.unit))
  // Frozen while dragging so the picture doesn't rescale under the pointer.
  readonly property var view: dragView || fitted
  readonly property bool editable: Apply.state === "idle"

  property string dragName: ""
  property var dragView: null
  property point dragStart
  property var dragOrigin: null
  property bool dragMoved: false

  function beginDrag(name, p) {
    select(name)
    if (!editable) return
    var cfg = Draft.config(name)
    dragName = name
    dragView = fitted
    dragStart = p
    dragOrigin = { x: cfg.x, y: cfg.y }
    dragMoved = false
  }

  function dragTo(p) {
    if (!dragName) return
    var dx = p.x - dragStart.x, dy = p.y - dragStart.y
    if (!dragMoved && Math.abs(dx) + Math.abs(dy) < 4) return
    dragMoved = true
    var r = D.rect(Draft.config(dragName))
    r.x = dragOrigin.x + dx / view.scale
    r.y = dragOrigin.y + dy / view.scale
    var pos = L.snap(r, Draft.placedRects(dragName), 12 / view.scale)
    Draft.move(dragName, pos.x, pos.y)
  }

  function endDrag() {
    if (dragName && dragMoved) {
      var pos = L.settle(D.rect(Draft.config(dragName)), Draft.placedRects(dragName))
      Draft.move(dragName, pos.x, pos.y)
    }
    dragName = ""
    dragView = null
  }

  color: Theme.alpha(Theme.foreground, 0.02)
  border.color: Theme.border
  radius: Theme.radius
  clip: true

  // Dot grid backdrop.
  Canvas {
    id: grid
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = Theme.alpha(Theme.foreground, 0.12)
      var step = Math.round(20 * Theme.unit)
      for (var x = step; x < width; x += step)
        for (var y = step; y < height; y += step)
          ctx.fillRect(x, y, 1, 1)
    }
    Connections {
      target: Theme
      function onForegroundChanged() { grid.requestPaint() }
    }
  }

  Text {
    anchors { left: parent.left; top: parent.top; margins: Theme.space.lg }
    text: root.placed.length
          ? "Desktop " + M.formatResolution(Math.round(root.layoutBounds.width), Math.round(root.layoutBounds.height)) + " logical px"
          : ""
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  Text {
    anchors { right: parent.right; top: parent.top; margins: Theme.space.lg }
    visible: root.editable && root.placed.length > 1
    text: "Drag to arrange"
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
  }

  Item {
    id: stage
    anchors {
      fill: parent
      bottomMargin: tray.visible ? tray.height + 2 * Theme.space.lg : 0
    }

    Repeater {
      model: root.placed

      MonitorTile {
        required property var modelData
        readonly property var size: M.logicalSize(modelData)
        // Inset by a pixel on each side so touching monitors read as separate.
        x: root.view.x + modelData.x * root.view.scale + 1
        y: root.view.y + modelData.y * root.view.scale + 1
        width: Math.max(8, size.width * root.view.scale - 2)
        height: Math.max(8, size.height * root.view.scale - 2)
        cfg: modelData
        monitor: Hypr.byName(modelData.name)
        number: Hypr.numberOf(modelData.name)
        selected: modelData.name === root.selectedName
        edited: Draft.isChanged(modelData.name)
        dragging: root.dragName === modelData.name && root.dragMoved
        draggable: root.editable
        onDragStarted: p => root.beginDrag(modelData.name, p)
        onDragMoved: p => root.dragTo(p)
        onDragEnded: root.endDrag()
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.configs.length === 0
    text: Hypr.error || "Waiting for Hyprland…"
    color: Hypr.error ? Theme.urgent : Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.body
  }

  Row {
    id: tray
    visible: root.others.length > 0
    anchors { left: parent.left; bottom: parent.bottom; margins: Theme.space.lg }
    spacing: Theme.space.md

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Not in layout"
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.caption
    }

    Repeater {
      model: root.others

      PButton {
        required property var modelData
        text: Hypr.numberOf(modelData.name) + "  " + modelData.name + " · "
              + (modelData.enabled ? "mirroring " + modelData.mirror : "off")
              + (Draft.isChanged(modelData.name) ? " · edited" : "")
        checked: modelData.name === root.selectedName
        onClicked: root.select(modelData.name)
      }
    }
  }
}
