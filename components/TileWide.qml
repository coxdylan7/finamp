import QtQuick
import qs.Commons

Rectangle {
  id: root
  property string title: ""
  property string count: ""
  property string subtitle: ""
  signal clicked()
  implicitHeight: 56
  radius: 12
  color: Util.alpha(Color.background, 0.9)
  border.width: 1
  border.color: Util.alpha(Color.foreground, 0.09)
  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: 10
    spacing: 10
    Rectangle {
      width: 40; height: 40; radius: 20
      color: Util.alpha(Color.accent, 0.14); border.width: 1; border.color: Util.alpha(Color.accent, 0.26)
      Text { anchors.centerIn: parent; text: root.title.slice(0, 1); color: Color.accent; font.family: Style.font.family; font.pixelSize: 15; font.bold: true }
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      width: parent.width - 58
      Text { text: root.title; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
      Text { text: root.count; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; width: parent.width }
      Text { text: root.subtitle; color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width }
    }
  }
  Text {
    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
    text: "›"; color: Util.alpha(Color.accent, 0.55); font.family: Style.font.family; font.pixelSize: 18
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: root.border.color = Util.alpha(Color.accent, 0.55)
    onExited: root.border.color = Util.alpha(Color.foreground, 0.09)
    onClicked: { root.clicked() }
  }
}