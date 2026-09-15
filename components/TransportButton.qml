import QtQuick
import qs.Commons

// Circular transport button — Winamp/VLC style, themed via Omarchy tokens.
Rectangle {
  id: root
  property string glyph: "▶"
  property string label: ""
  property string tooltip: ""
  property bool active: false
  property bool selected: false
  property int glyphSize: 15
  signal clicked()

  width: 34
  height: 34
  radius: 17
  color: root.selected ? Util.alpha(Color.accent, 0.22)
       : (ac.containsMouse ? Util.alpha(Color.foreground, 0.14) : Util.alpha(Color.foreground, 0.05))
  border.width: 1
  border.color: root.selected ? Util.alpha(Color.accent, 0.55)
              : (ac.containsMouse ? Util.alpha(Color.accent, 0.5) : Util.alpha(Color.foreground, 0.1))

  Behavior on color { ColorAnimation { duration: 120 } }

  Column {
    anchors.centerIn: parent
    spacing: 1
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.glyph
      color: root.selected ? Color.accent : (root.active ? Color.urgent : Util.alpha(Color.foreground, 0.9))
      font.family: Style.font.family
      font.pixelSize: root.glyphSize
      font.bold: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.label !== ""
      text: root.label
      color: Util.alpha(Color.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: 8
      font.bold: true
    }
  }

  MouseArea {
    id: ac
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}