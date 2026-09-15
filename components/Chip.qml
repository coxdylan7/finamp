import QtQuick
import qs.Commons

Rectangle {
  id: root
  property string text: ""
  property string value: ""
  signal clicked()
  implicitHeight: 44
  implicitWidth: 170
  radius: 10
  color: Util.alpha(Color.foreground, 0.04)
  border.width: 1
  border.color: Util.alpha(Color.foreground, 0.08)
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: 8
    spacing: 1
    Text { text: root.text; color: Util.alpha(Color.foreground, 0.55); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
    Text { text: root.value; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight; width: parent.width }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: root.border.color = Util.alpha(Color.accent, 0.55)
    onExited: root.border.color = Util.alpha(Color.foreground, 0.08)
    onClicked: { root.clicked() }
  }
}