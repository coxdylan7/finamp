import QtQuick
import qs.Commons

Rectangle {
  id: root
  property string title: ""
  property string value: ""
  property string sub: ""
  signal clicked()
  implicitHeight: 64
  radius: 10
  color: Util.alpha(Color.foreground, 0.04)
  border.width: 1
  border.color: Util.alpha(Color.foreground, 0.07)
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: 9
    spacing: 2
    Text { text: root.title; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
    Text { text: root.value; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; width: parent.width }
    Text { text: root.sub; color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width }
  }
  Text {
    anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
    text: "›"; color: Util.alpha(Color.accent, 0.55); font.family: Style.font.family; font.pixelSize: 16
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: root.border.color = Util.alpha(Color.accent, 0.55)
    onExited: root.border.color = Util.alpha(Color.foreground, 0.07)
    onClicked: { root.clicked() }
  }
}