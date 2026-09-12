import QtQuick
import QtQuick.Layouts
import "../services"

// Small uppercase heading with a rule under it.
ColumnLayout {
  id: root

  property string title

  Layout.fillWidth: true
  Layout.topMargin: Theme.space.sm
  spacing: Theme.space.xs

  Text {
    text: root.title.toUpperCase()
    color: Theme.muted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.font.caption
    font.letterSpacing: 1
    font.bold: true
    Accessible.role: Accessible.Heading
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: Theme.border
  }
}
