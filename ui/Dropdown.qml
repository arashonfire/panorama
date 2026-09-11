import QtQuick
import QtQuick.Controls
import qs.services

// Compact select: a button showing the current option that opens a list.
// `options` is [{ value, label }]; the owner updates `value` on `picked`.
Item {
  id: root

  property var options: []
  property var value
  property string accessibleName
  signal picked(var value)

  readonly property int currentIndex: {
    for (var i = 0; i < options.length; i++) {
      if (String(options[i].value) === String(value)) return i
    }
    return -1
  }

  function pickRelative(delta) {
    var i = currentIndex + delta
    if (i >= 0 && i < options.length) picked(options[i].value)
  }

  implicitWidth: Math.round(220 * Theme.unit)
  implicitHeight: Theme.controlHeight
  opacity: enabled ? 1 : 0.4

  activeFocusOnTab: true
  Accessible.role: Accessible.ComboBox
  Accessible.name: accessibleName
  Accessible.description: currentIndex >= 0 ? options[currentIndex].label : ""
  Keys.onReturnPressed: popup.open()
  Keys.onSpacePressed: popup.open()
  Keys.onUpPressed: pickRelative(-1)
  Keys.onDownPressed: pickRelative(1)

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius
    color: mouse.containsMouse || popup.opened ? Theme.hover : Theme.alpha(Theme.foreground, 0.04)
    border.width: 1
    border.color: root.activeFocus || popup.opened ? Theme.accent : Theme.alpha(Theme.foreground, mouse.containsMouse ? 0.4 : 0.25)

    Text {
      anchors {
        left: parent.left
        right: chevron.left
        verticalCenter: parent.verticalCenter
        leftMargin: Theme.space.md
        rightMargin: Theme.space.sm
      }
      text: root.currentIndex >= 0 ? root.options[root.currentIndex].label : ""
      elide: Text.ElideRight
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.body
    }

    Text {
      id: chevron
      anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Theme.space.md }
      text: "▾"
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.font.body
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: popup.opened ? popup.close() : popup.open()
    }
  }

  Popup {
    id: popup
    y: root.height + Theme.space.xs
    width: root.width
    height: Math.min(list.contentHeight, Math.round(280 * Theme.unit)) + 2
    padding: 1
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: list.positionViewAtIndex(Math.max(0, root.currentIndex), ListView.Contain)

    background: Rectangle {
      color: Theme.background
      radius: Theme.radius
      border.color: Theme.alpha(Theme.foreground, 0.35)
    }

    contentItem: ListView {
      id: list
      clip: true
      model: root.options
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Rectangle {
        required property var modelData
        required property int index
        width: ListView.view.width
        height: Theme.controlHeight
        color: rowMouse.containsMouse ? Theme.hover : index === root.currentIndex ? Theme.selected : "transparent"

        Text {
          anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: Theme.space.md
            rightMargin: Theme.space.md
          }
          text: modelData.label
          elide: Text.ElideRight
          color: index === root.currentIndex ? Theme.accent : Theme.foreground
          font.family: Theme.fontFamily
          font.pixelSize: Theme.font.body
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.picked(modelData.value)
            popup.close()
          }
        }
      }
    }
  }
}
