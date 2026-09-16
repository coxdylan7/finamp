import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "components" as Comp
import "FinAmp.js" as T

BarWidget {
  id: root
  moduleName: "djc.finamp"

  readonly property var service: {
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return null
    return bar.shell.serviceFor("djc.finamp")
  }
  readonly property bool ready: service !== null
  readonly property bool playing: ready ? service.phase === "playing" : false
  readonly property string nowTitle: ready && service.current ? String(service.current.name || "") : ""
  readonly property string nowMeta: ready && service.current ? (String(service.current.artist || "") + (service.current.album ? " · " + service.current.album : "")).trim() : ""
  readonly property string waveText: {
    var t = (root.playing && root.nowTitle) ? root.nowTitle : "FINAMP"
    if (t.length > 26) t = t.slice(0, 25) + "…"
    return t
  }

  readonly property bool isSaved: ready && service.current ? service.isDownloaded(service.current) : false
  readonly property bool dlActive: ready && service.downloading
  readonly property string statusLine: {
    if (!ready) return "…"
    if (service.downloading) return "⤓ downloading “" + String(service.pendingDownloadName || "…") + "” → " + (service.downloadDirPath || "Downloads/finamp")
    if (service.current && service.isDownloaded(service.current)) return "saved ✓ " + (service.downloadedPathFor(service.current) || "")
    return String(service.statusText || "")
  }

  function nextUp() {
    var s = root.service
    if (!s) return []
    var q = s.queue || []
    if (q.length > 1) {
      var i = s.queueIndex >= 0 ? s.queueIndex + 1 : 0
      var out = []
      var guard = 0
      while (out.length < 6 && guard < q.length * 2) {
        guard++
        if (!q[i]) break
        out.push(q[i])
        i = (i + 1) % q.length
      }
      return out
    }
    var items = s.dataItems || []
    var pool = []
    for (var k = 0; k < items.length; k++) { var it = items[k]; if (it && !it.isFolder && (!s.current || String(it.id) !== String(s.current.id))) pool.push(it) }
    if (s.shuffle) pool.sort(function(){ return Math.random() - 0.5 })
    return pool.slice(0, 8)
  }

  implicitWidth: Math.max(96, T.textAdvance(root.waveText, 11) + 14)
  implicitHeight: bar ? bar.barSize : 28

  property bool hoverOpen: false

  Rectangle { anchors.fill: parent; color: "transparent"; radius: 6 }

  Item {
    anchors.centerIn: parent
    width: T.textAdvance(root.waveText, 11) + 6
    height: 22
    Comp.WavySprite {
      anchors.centerIn: parent
      phase: 0
      capturing: root.playing
      text: root.waveText
      fontSize: 11
      baseColor: root.playing ? Color.urgent : (ready && service.serverUrl ? Color.accent : Util.alpha(Color.foreground, 0.85))
    }
  }

  HoverHandler {
    id: hoverHandler
    onHoveredChanged: {
      if (hovered) root.hoverOpen = true
      else if (!popup.containsMouse) root.hoverOpen = false
    }
  }
  MouseArea {
    anchors.fill: parent
    z: 10
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: {
      if (service && service.toggleDash) service.toggleDash()
      root.hoverOpen = false
    }
    onEntered: {
      root.hoverOpen = true
      if (bar && bar.showTooltip) bar.showTooltip(root, root.nowTitle ? ("▶ " + root.nowTitle + (root.nowMeta ? " — " + root.nowMeta : "")) : (ready ? (service.statusText || "FINAMP") : "Loading…"))
    }
    onExited: {
      if (!popup.containsMouse) root.hoverOpen = false
      if (bar && bar.hideTooltip) bar.hideTooltip(root)
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.hoverOpen && !(ready && !!service.dashVisible)
    triggerMode: "hover"
    contentWidth: Math.min(420, Style.space(400))
    contentHeight: Math.min(560, Style.space(560))
    onVisibleChanged: if (!visible) root.hoverOpen = false
    onContainsMouseChanged: {
      if (containsMouse) root.hoverOpen = true
      else if (!hoverHandler.hovered) root.hoverOpen = false
    }

    ColumnLayout {
      width: parent.width - Style.space(16)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(12)
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Comp.WavySprite { Layout.preferredWidth: 72; Layout.preferredHeight: 22; capturing: root.playing; text: "FINAMP"; fontSize: 11; baseColor: root.playing ? Color.urgent : Color.accent }
        Column { Layout.fillWidth: true; spacing: 1
          Text { width: parent.width; text: root.nowTitle || "Nothing playing"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight }
          Text { width: parent.width; text: root.nowMeta || (ready ? (service.serverName ? service.serverName + " · " + service.serverUrl : "no server yet — open Settings") : "…"); color: Util.alpha(Color.foreground, 0.55); font.family: Style.font.family; font.pixelSize: 10; elide: Text.ElideRight }
        }
        Rectangle { Layout.preferredWidth: 34; Layout.preferredHeight: 22; radius: 11; color: root.playing ? Util.alpha(Color.urgent, 0.15) : Util.alpha(Color.accent, 0.12); border.width: 1; border.color: Util.alpha(root.playing ? Color.urgent : Color.accent, 0.3); Text { anchors.centerIn: parent; text: root.playing ? "▶" : "■"; color: root.playing ? Color.urgent : Color.accent; font.family: Style.font.family; font.pixelSize: 10; font.bold: true } }
      }

      Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, 0.08) }

      // Mini transport
      RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Comp.TransportButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; glyph: "◀◀"; glyphSize: 11; onClicked: { if (service) service.playPrev() } }
        Comp.TransportButton { Layout.preferredWidth: 40; Layout.preferredHeight: 40; glyph: root.playing ? "❚❚" : "▶"; glyphSize: 16; selected: root.playing; onClicked: { if (service) service.togglePlay() } }
        Comp.TransportButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; glyph: "▶▶"; glyphSize: 11; onClicked: { if (service) service.playNext() } }
        Item { Layout.fillWidth: true }
        Comp.TransportButton { Layout.preferredWidth: 74; Layout.preferredHeight: 30; radius: 15; glyph: root.dlActive ? "…" : (root.isSaved ? "✓" : "⤓"); label: root.dlActive ? "SAVING" : root.isSaved ? "OFFLOAD" : "SAVE"; glyphSize: 11; selected: root.isSaved; onClicked: { if (service) root.isSaved ? service.offload(service.current) : service.download(service.current) } }
        Comp.TransportButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; glyph: "↗"; glyphSize: 12; onClicked: { if (service) service.openInMpv(service.current) } }
      }

      Text { Layout.fillWidth: true; text: "library " + (service ? (service.dataItems.length + " items") : "…") + " · " + (service ? (service.queue.length + " queued") : ""); color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }

      Text { Layout.fillWidth: true; text: root.statusLine; color: root.dlActive ? Color.accent : Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }

      Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, 0.08); visible: root.nextUp().length > 0 }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: root.nextUp().length > 0
        Text { Layout.fillWidth: true; text: root.service && root.service.queue && root.service.queue.length > 1 ? "UP NEXT" : "NEXT"; color: Util.alpha(Color.accent, 0.9); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
        Repeater {
          model: root.nextUp()
          delegate: RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 6
            Text { text: String(index + 1); color: Util.alpha(Color.foreground, 0.5); font.pixelSize: 9 }
            Text { Layout.fillWidth: true; text: modelData.name || (modelData.id || "?"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10; elide: Text.ElideRight }
            Text { text: modelData.artist || ""; color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text { Layout.fillWidth: true; text: "Click to open Finamp · ⌥ drag queue"; color: Util.alpha(Color.foreground, 0.38); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
        Rectangle { Layout.preferredWidth: 28; Layout.preferredHeight: 20; radius: 8; color: Util.alpha(Color.accent, 0.12); border.width: 1; border.color: Util.alpha(Color.accent, 0.22); Text { anchors.centerIn: parent; text: "↗"; color: Color.accent; font.pixelSize: 10 } MouseArea { anchors.fill: parent; onClicked: if (service && service.toggleDash) service.toggleDash() } }
      }
    }
  }
}