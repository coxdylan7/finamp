import QtQuick

Item {
  id: root
  property real phase: 0
  property bool capturing: false
  property string text: "FINAMP"
  property int fontSize: 14
  property color baseColor: capturing ? "#ff4444" : "#00e5ff"
  property bool showTerminalHint: false

  width: 72
  height: 28

  // Wavy text
  Row {
    anchors.centerIn: parent
    spacing: 1
    Repeater {
      model: root.text.length
      delegate: Text {
        required property int index
        text: root.text.charAt(index)
        font.family: "monospace"
        font.pixelSize: root.fontSize
        font.bold: true
        color: root.baseColor
        opacity: root.capturing ? 0.9 : 0.85
        y: Math.sin(root.phase * 0.06 + index * 0.85) * 3 + Math.cos(root.phase * 0.04 + index * 0.6) * 1.2
        // Glow when capturing
        style: Text.Outline
        styleColor: root.capturing ? Qt.rgba(1,0.2,0.2,0.35) : Qt.rgba(0,0.9,1,0.12)
      }
    }
  }

  SequentialAnimation on opacity {
    running: root.capturing
    loops: Animation.Infinite
    NumberAnimation { to: 0.55; duration: 420; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
  }

  NumberAnimation on phase {
    running: true
    loops: Animation.Infinite
    from: 0; to: 360
    duration: 2200
    easing.type: Easing.Linear
  }
}
