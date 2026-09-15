import QtQuick
import qs.Commons

// Fake spectrum analyzer — Winamp-style bars, animated while playing.
Item {
  id: root
  property bool active: false
  property int bands: 24
  property color baseColor: Color.accent

  implicitWidth: 300
  implicitHeight: 56

  property var heights: (function(){ var a=[]; for (var i=0;i<root.bands;i++) a.push(0.2); return a })()

  Timer {
    interval: 75
    repeat: true
    running: root.active && root.visible
    onTriggered: {
      var a = []
      for (var i=0;i<root.bands;i++) {
        var bass = i < root.bands/4 ? 0.6 : (i > root.bands*3/4 ? 0.4 : 0.85)
        a.push(Math.max(0.08, Math.min(1.0, 0.15 + Math.random()*bass)))
      }
      root.heights = a
    }
  }

  Repeater {
    model: root.bands
    delegate: Rectangle {
      required property int index
      width: Math.max(2, root.width / root.bands - 2)
      height: Math.max(2, root.height * (root.heights && root.heights[index] ? root.heights[index] : 0.2))
      radius: width / 2
      anchors.bottom: root.bottom
      x: index * (root.width / root.bands)
      color: Util.alpha(root.baseColor, 0.28 + 0.62 * ((index & 3) / 3))
    }
  }
}