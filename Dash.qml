import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import QtQuick.Controls 2.15
import "components" as Comp
import "FinAmp.js" as T

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var service: null
  property var svc: service ? service : null
  readonly property bool ready: svc !== null
  readonly property bool dashVisible: ready ? !!svc.dashVisible : false

  Timer {
    id: svcTimer
    interval: 200
    repeat: true
    running: root.svc === null
    onTriggered: {
      var s = root.service ? root.service : (root.shell && typeof root.shell.serviceFor === "function" ? root.shell.serviceFor("djc.finamp") : null)
      if (s) root.svc = s
    }
  }

  property bool settingsOpen: false
  property bool eqOpen: false
  property string pendingPlName: ""
  property bool seekDrag: false
  property real volume: 1.0
  property real speed: 1.0
  readonly property bool isVideo: media.hasVideo
  readonly property bool hasCurrent: svc && svc.current !== null
  property bool kindDropOpen: false
  property var playlistPickerTarget: null
  property string viewMode: "library"    // library | queue | playlists
  property string viewingPlaylistId: ""  // non-empty when drilling into a playlist's items
  function setView(m) {
    root.viewMode = m
    root.viewingPlaylistId = ""
    if (svc) svc.showQueue = (m === "queue")
  }

  function kindOptions() {
    if (svc && svc.libraryOnly === "music")
      return [{ label: "All", value: "all" }, { label: "Artists", value: "MusicArtist" }, { label: "Albums", value: "MusicAlbum" }, { label: "Songs", value: "Audio" }]
    return [{ label: "All", value: "all" }, { label: "Movies", value: "Movie" }, { label: "Shows", value: "Series" }, { label: "Episodes", value: "Episode" }, { label: "Albums", value: "MusicAlbum" }, { label: "Songs", value: "Audio" }, { label: "Artists", value: "MusicArtist" }, { label: "Videos", value: "Video" }]
  }
  function filterLabel() {
    var o = root.kindOptions()
    var k = svc ? svc.kind : "all"
    for (var i = 0; i < o.length; i++) if (o[i].value === k) return o[i].label
    return "All"
  }

  // ---- derived library rows ----
  function libraryRows() {
    var rows = []
    if (!ready) return rows
    var items = svc.dataItems
    var k = svc.kind
    var q = svc.query.trim().toLowerCase()
    var par = svc.parentFilter
    var idParent = {}
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].id) idParent[String(items[i].id)] = String(items[i].parentId || "")
    function isWithin(id, top) {
      var cur = String(id); var guard = 0
      while (cur && guard++ < 40) { if (cur === top) return true; cur = idParent[String(cur)] || "" }
      return false
    }
    var out = []
    for (var i2 = 0; i2 < items.length; i2++) {
      var it = items[i2]
      if (!it) continue
      if (String(it.id) === par) continue
      if (par && !isWithin(String(it.id), par)) continue
      if (k !== "all" && String(it.type) !== k) continue
      if (q && String(it.name + " " + it.artist + " " + it.album).toLowerCase().indexOf(q) === -1) continue
      out.push(it)
    }
    out.sort(function(a, b){ return String(a.name).localeCompare(String(b.name)) })
    return out
  }
  function queueRows() {
    var out = []
    if (!ready) return out
    for (var i = 0; i < svc.queue.length; i++) out.push({ it: svc.queue[i], cur: i === svc.queueIndex, idx: i })
    return out
  }
  function isDownloaded(rec) { return !!svc && svc.isDownloaded(rec) }
  function inQueue(rec) { return !!svc && svc.isInQueue(rec) }
  function playlistName() { if (!svc || !svc.activePlaylistId) return ""; var p = svc.playlistForId(svc.activePlaylistId); return p ? String(p.name || "") : "" }
  function createFromInput() {
    var n = String(root.pendingPlName || "").trim()
    if (!n) return
    if (svc) svc.createPlaylist(n)
    root.pendingPlName = ""
    plNewInput.text = ""
  }
  function playlistRows() {
    var out = []
    if (!svc) return out
    var pls = svc.playlists || []
    for (var i = 0; i < pls.length; i++) out.push({ playlist: pls[i], idx: i })
    return out
  }
  function playlistItemRows() {
    var out = []
    if (!svc || !root.viewingPlaylistId) return out
    var p = svc.playlistForId(root.viewingPlaylistId)
    if (!p) return out
    var map = {}
    for (var i = 0; i < svc.dataItems.length; i++) { var it = svc.dataItems[i]; if (it && it.id) map[String(it.id)] = it }
    var ids = p.itemIds || []
    for (var j = 0; j < ids.length; j++) {
      var rec = map[String(ids[j])]
      if (rec && !rec.isFolder) out.push({ it: rec, idx: j, cur: svc.current && String(svc.current.id) === String(rec.id) })
    }
    return out
  }
  function inPlaylist(pl, rec) {
    if (!pl || !rec || !rec.id) return false
    var key = String(rec.id)
    var ids = pl.itemIds || []
    for (var i = 0; i < ids.length; i++) if (String(ids[i]) === key) return true
    return false
  }
  function parentPath() {
    var names = []
    var id = svc ? svc.parentFilter : ""
    var guard = 0
    while (id && guard++ < 24) {
      var found = null
      for (var i = 0; i < svc.dataItems.length; i++) if (String(svc.dataItems[i].id) === String(id)) { found = svc.dataItems[i]; break }
      if (!found) break
      names.unshift(String(found.name || "?"))
      id = found.parentId ? String(found.parentId) : ""
    }
    return names.join(" › ") || "…"
  }
  function parentName() {
    if (!ready || !svc.parentFilter) return ""
    for (var i = 0; i < svc.dataItems.length; i++) if (String(svc.dataItems[i].id) === String(svc.parentFilter)) return String(svc.dataItems[i].name)
    return "…"
  }
  function playPause() {
    if (svc) svc.togglePlay()
  }
  function seekBy(deltaMs) {
    if (!ready) return
    var t = Math.max(0, (media.duration ? media.position : 0) + deltaMs)
    if (media.seek) media.seek(t)
    else media.position = t
  }
  function volBy(delta) { root.volume = Math.max(0, Math.min(1.25, root.volume + delta)) }

  function openSettings() { root.settingsOpen = true; if (svc) { serverInput.text = svc.serverUrl; apiInput.text = svc.apiKey; userInput.text = svc.userId } }
  function closeSettings() { root.settingsOpen = false }
  function saveServer() { if (!svc) return; svc.statusText = "saving serverUrl…"; svc.saveKey("serverUrl", serverInput.text.trim()); Qt.callLater(function(){ svc.fetchMedia(serverInput.text.trim(), svc.apiKey) }) }
  function saveApiKey() { if (!svc) return; svc.statusText = "saving apiKey…"; svc.saveKey("apiKey", apiInput.text.trim()); Qt.callLater(function(){ svc.fetchMedia(svc.serverUrl, apiInput.text.trim()) }) }
  function saveUserId() { if (!svc) return; svc.statusText = "saving userId…"; svc.saveKey("userId", userInput.text.trim()); Qt.callLater(function(){ svc.fetchMedia(svc.serverUrl, svc.apiKey) }) }

  function discoverNow() { if (svc) svc.discover() }

  // ---- playback primitives ----
  AudioOutput { id: audio; volume: Math.min(1, root.volume) }
  MediaPlayer {
    id: media
    audioOutput: audio
    videoOutput: videoOut2
    playbackRate: root.speed
    onPlaybackStateChanged: { if (svc) { if (media.playbackState === MediaPlayer.StoppedState && media.position >= (media.duration||0) - 1000) svc.playNext(); svc.phase = media.playbackState === MediaPlayer.PlayingState ? "playing" : (media.playbackState === MediaPlayer.PausedState ? "paused" : "stopped") } }
    onErrorOccurred: function(error, errStr) { if (error !== MediaPlayer.NoError && svc) svc.statusText = "playback: " + errStr }
  }

  function startPlayback() {
    if (!svc.current) { console.log("finamp startPlayback: no current"); return }
    var u = svc.streamUrl(svc.current, false)
    console.log("finamp startPlayback:", u && u.slice(0,120))
    media.stop()
    media.source = u
    media.play()
  }

  Connections {
    target: svc
    function onCurrentChanged() { root.startPlayback() }
    function onPhaseChanged() {
      if (!svc.current) return
      if (svc.phase === "paused") media.pause()
      else if (svc.phase === "playing" && media.source) media.play()
      else if (svc.phase === "playing") root.startPlayback()
      else if (svc.phase === "stopped") media.stop()
    }
  }

  onDashVisibleChanged: if (svc && !svc.dashVisible) root.settingsOpen = false

  onSvcChanged: console.log("finamp Dash: svc " + (svc ? "yes dashVisible=" + svc.dashVisible : "null"))

Component.onCompleted: console.log("finamp Dash: ready=" + ready)

  // ================= PLAYER WINDOW =================
  PanelWindow {
    id: win
    visible: root.dashVisible
    screen: Quickshell.screens[0]
    anchors { top: true; left: true; right: true; bottom: true }
    color: Util.alpha(Color.background, 0.88)
    WlrLayershell.namespace: "omarchy-finamp"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    MouseArea { anchors.fill: parent; onClicked: { if (svc && svc.toggleDash) svc.toggleDash() } }

    Rectangle {
      id: card
      width: Math.min(parent.width * 0.92, 1220)
      height: Math.min(parent.height * 0.9, 820)
      anchors.centerIn: parent
      radius: 22
      color: Util.alpha(Color.background, 0.96)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.14)
      layer.enabled: true

      Rectangle {
        id: dashContent
        anchors.fill: parent; radius: 22; clip: true; color: "transparent"
        focus: root.dashVisible
        Keys.onSpacePressed: { event.accepted = true; root.playPause() }
        Keys.onLeftPressed: { event.accepted = true; root.seekBy(-5000) }
        Keys.onRightPressed: { event.accepted = true; root.seekBy(5000) }
        Keys.onUpPressed: { event.accepted = true; root.volBy(0.05) }
        Keys.onDownPressed: { event.accepted = true; root.volBy(-0.05) }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_L) { event.accepted = true; root.setView(svc && svc.showQueue ? "library" : "queue") }
          else if (event.key === Qt.Key_M) { event.accepted = true; root.volume = root.volume > 0 ? 0 : 1.0 }
          else if (event.key === Qt.Key_Escape) { event.accepted = true; if (kindPopup.opened) kindPopup.close(); if (playlistPopup.opened) playlistPopup.close(); root.settingsOpen = false }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 16
          spacing: 10

          // ============ HEADER ============
          RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Comp.WavySprite { Layout.preferredWidth: 96; Layout.preferredHeight: 26; capturing: media.playbackState === MediaPlayer.PlayingState; text: "FINAMP"; fontSize: 13; baseColor: media.playbackState === MediaPlayer.PlayingState ? Color.urgent : Color.accent }
            Rectangle {
              Layout.fillWidth: true; Layout.preferredHeight: 26; radius: 10
              color: svc && svc.mediaOk ? Util.alpha(Color.accent, 0.08) : Util.alpha(Color.urgent, 0.1)
              border.width: 1; border.color: Util.alpha(svc && svc.mediaOk ? Color.accent : Color.urgent, 0.25)
              RowLayout { anchors.fill: parent; anchors.margins: 8; spacing: 6
                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: (svc ? (String(svc.serverName||"") + " · jf " + String(svc.serverVersion||"") + " · " + svc.dataItems.length + " items") : "no server") + (svc && svc.wizardPending ? " — finish server setup" : ""); color: svc && svc.mediaOk ? Util.alpha(Color.foreground,0.8) : Util.alpha(Color.foreground,0.55); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
                Text { text: svc && svc.mediaOk ? "●" : "○"; color: svc && svc.mediaOk ? Color.accent : Color.urgent; font.pixelSize: 9 }
              }
            }
            Comp.TransportButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; glyph: "⚙"; glyphSize: 13; selected: root.settingsOpen; onClicked: root.settingsOpen = !root.settingsOpen }
            Comp.TransportButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; glyph: "↻"; glyphSize: 13; onClicked: { if (svc) svc.refresh() } }
            Comp.TransportButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; glyph: "✕"; glyphSize: 12; onClicked: { if (svc && svc.toggleDash) svc.toggleDash() } }
          }

          // ============ STATUS STRIP ============
          Text {
            Layout.fillWidth: true
            text: svc ? (svc.statusText || "") : "…"
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family; font.pixelSize: 9
            elide: Text.ElideRight
          }

          Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, 0.08) }

          // ============ BODY ============
          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // -------- left: player pane (Winamp) --------
            ColumnLayout {
              Layout.preferredWidth: 392
              Layout.fillHeight: true
              spacing: 10

              // art / video area
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 232
                radius: 14
                color: Util.alpha(Color.background, 0.9)
                border.width: 1
                border.color: Util.alpha(Color.foreground, 0.1)
                clip: true

                Image {
                  id: artImg
                  anchors.fill: parent
                  source: hasCurrent ? svc.imageUrl(svc.current, 600) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  visible: !isVideo
                }
                VideoOutput {
                  id: videoOut2
                  anchors.fill: parent
                  fillMode: VideoOutput.PreserveAspectFit
                  visible: isVideo
                }

                Rectangle { anchors.fill: parent; visible: !hasCurrent; color: Util.alpha(Color.foreground, 0.03) }
                Text { anchors.centerIn: parent; visible: !hasCurrent; text: "♩ ♪ ♫ — Finamp — pick something from the library"; color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 11; font.bold: true }

                // spectrum overlay bottom
                Rectangle {
                  anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                  height: 44
                  gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Util.alpha(Color.background, 0.85) }
                  }
                  Comp.Spectrum {
                    anchors.fill: parent
                    anchors.margins: 5
                    active: media.playbackState === MediaPlayer.PlayingState
                    baseColor: isVideo ? Util.alpha(Color.foreground, 0.85) : Color.accent
                  }
                }
              }

              // now playing meta
              Column {
                Layout.fillWidth: true
                spacing: 1
                Text { width: parent.width; text: hasCurrent ? String(svc.current.name || "") : "—"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                Text { width: parent.width; text: hasCurrent ? (String(svc.current.artist||"") + (svc.current.album ? " · " + svc.current.album : "") + (svc.current.year ? " · " + svc.current.year : "")).trim() : "—"; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 11; elide: Text.ElideRight }
                Text { width: parent.width; text: hasCurrent ? ("type " + String(svc.current.type||"") + (svc.current.runtimeMs ? " · " + T.formatMs(svc.current.runtimeMs) : "")) : ""; color: Util.alpha(Color.foreground, 0.42); font.family: Style.font.family; font.pixelSize: 9 }
              }

              // transport
              RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Comp.TransportButton { Layout.preferredWidth: 34; Layout.preferredHeight: 34; glyph: "◀◀"; onClicked: { if (svc) svc.playPrev() } }
                Comp.TransportButton { Layout.preferredWidth: 48; Layout.preferredHeight: 48; glyph: media.playbackState === MediaPlayer.PlayingState ? "❚❚" : "▶"; glyphSize: 20; selected: media.playbackState === MediaPlayer.PlayingState; onClicked: root.playPause() }
                Comp.TransportButton { Layout.preferredWidth: 34; Layout.preferredHeight: 34; glyph: "▶▶"; onClicked: { if (svc) svc.playNext() } }
                Comp.TransportButton { Layout.preferredWidth: 34; Layout.preferredHeight: 34; glyph: "◼"; glyphSize: 13; onClicked: { if (svc) svc.phase = "stopped" } }
                Item { Layout.fillWidth: true }
                Comp.TransportButton { Layout.preferredWidth: 34; Layout.preferredHeight: 34; glyph: "↗"; glyphSize: 12; onClicked: { if (svc) svc.openInMpv(svc.current) } }
                Comp.TransportButton { Layout.preferredWidth: 74; Layout.preferredHeight: 34; radius: 17; glyph: svc && svc.downloading ? "…" : (svc && svc.current && svc.isDownloaded(svc.current) ? "✓" : "⤓"); label: svc && svc.downloading ? "SAVING" : svc && svc.current && svc.isDownloaded(svc.current) ? "OFFLOAD" : "SAVE"; glyphSize: 12; selected: svc && svc.current && svc.isDownloaded(svc.current); onClicked: { if (svc && svc.current) svc.isDownloaded(svc.current) ? svc.offload(svc.current) : svc.download(svc.current) } }
              }

              // seek
              Column {
                Layout.fillWidth: true
                spacing: 2
                RowLayout { Layout.fillWidth: true; spacing: 6
                  Text { text: T.formatClock(media.position); color: Util.alpha(Color.foreground, 0.7); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                  PanelSlider {
                    id: seekBar
                    bar: sliderBar
                    Layout.fillWidth: true
                    minimum: 0
                    maximum: media.duration > 0 ? media.duration : 1
                    value: root.seekDrag ? seekBar.liveValue : Math.min(maximum, media.position)
                    step: 1000
                    onMoved: root.seekDrag = true
                    onReleased: function(v) { root.seekDrag = false; if (media.seek) media.seek(v) }
                  }
                  Text { text: "-" + T.formatClock(Math.max(0, media.duration - media.position)); color: Util.alpha(Color.foreground, 0.7); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                }
              }

              // volume + speed
              RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "🔊"; color: Util.alpha(Color.foreground, 0.6); font.pixelSize: 10 }
                PanelSlider { id: volBar; bar: sliderBar; Layout.fillWidth: true; minimum: 0; maximum: 1.25; value: root.volume; step: 0.05; onMoved: root.volume = value; onReleased: root.volume = value }
                Text { text: Math.round(root.volume * 100) + "%"; color: Util.alpha(Color.foreground, 0.55); font.family: Style.font.family; font.pixelSize: 9 }
                Item { Layout.preferredWidth: 6 }
                Text { text: "1×"; color: Util.alpha(Color.foreground, 0.6); font.pixelSize: 10 }
                PanelSlider { id: speedBar; bar: sliderBar; Layout.preferredWidth: 90; minimum: 0.25; maximum: 4; value: root.speed; step: 0.25; onMoved: root.speed = value; onReleased: root.speed = value }
                Text { text: root.speed.toFixed(2) + "×"; color: Util.alpha(Color.foreground, 0.55); font.family: Style.font.family; font.pixelSize: 9 }
              }

              // shuffle / repeat / eq
              RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Comp.TransportButton { width: 60; height: 30; radius: 15; Layout.preferredWidth: 60; Layout.preferredHeight: 30; label: "SHUF"; glyph: "🔀"; glyphSize: 11; selected: svc ? svc.shuffle : false; onClicked: { if (svc) svc.shuffle = !svc.shuffle } }
                Comp.TransportButton { width: 60; height: 30; radius: 15; Layout.preferredWidth: 60; Layout.preferredHeight: 30; label: "REP"; glyph: "🔁"; glyphSize: 11; selected: svc ? svc.repeat : false; onClicked: { if (svc) svc.repeat = !svc.repeat } }
                Item { Layout.fillWidth: true }
                      Comp.TransportButton { width: 60; height: 30; radius: 15; Layout.preferredWidth: 60; Layout.preferredHeight: 30; label: "EQ"; glyph: "〽"; glyphSize: 11; selected: root.eqOpen; onClicked: root.eqOpen = !root.eqOpen }
                      Comp.TransportButton { width: 70; height: 30; radius: 15; Layout.preferredWidth: 70; Layout.preferredHeight: 30; label: "SI"; glyph: "∿"; glyphSize: 11; onClicked: { if (svc) svc.cycleSpectrum() } }
              }

              // Winamp EQ
              Column {
                Layout.fillWidth: true
                visible: root.eqOpen
                spacing: 4
                RowLayout { Layout.fillWidth: true; spacing: 3
                  Repeater {
                    model: ["60","170","310","600","1k","3k","6k","12k","14k","16k"]
                    delegate: Column {
                      required property string modelData
                      required property int index
                      Layout.fillWidth: true
                      spacing: 2
                      PanelSlider { bar: sliderBar; width: 24; height: 56; Layout.preferredWidth: 24; Layout.preferredHeight: 56; minimum: -12; maximum: 12; value: root.eqBands[index] || 0; step: 1; onMoved: root.eqBands[index] = value }
                      Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData; color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 7; font.bold: true }
                    }
                  }
                }
                Text { Layout.fillWidth: true; text: "Winamp EQ — preset: " + (root.eqOpen ? "Classic v2.9" : ""); color: Util.alpha(Color.foreground, 0.35); font.family: Style.font.family; font.pixelSize: 8 }
              }
            }

            // -------- right: library --------
            ColumnLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              spacing: 8

              // mode tabs + library browse controls
              RowLayout {
                Layout.fillWidth: true
                spacing: 6
                z: 3
                Repeater {
                  model: [
                    { m: "library",   g: "▦", l: "LIBRARY" },
                    { m: "queue",     g: "⧉", l: "QUEUE" },
                    { m: "playlists", g: "▤", l: "PLAYLISTS" }
                  ]
                  delegate: Rectangle {
                    required property var modelData
                    Layout.preferredWidth: 94; Layout.preferredHeight: 26
                    radius: 13
                    color: root.viewMode === modelData.m ? Util.alpha(Color.accent, 0.2) : Util.alpha(Color.foreground, 0.05)
                    border.width: 1
                    border.color: root.viewMode === modelData.m ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.accent, 0.3)
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 5
                      Text { text: modelData.g; color: root.viewMode === modelData.m ? Color.accent : Util.alpha(Color.foreground, 0.6); font.pixelSize: 10 }
                      Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.l; color: root.viewMode === modelData.m ? Color.accent : Util.alpha(Color.foreground, 0.75); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                      Text { visible: modelData.m === "queue" && svc; text: svc ? String(svc.queue.length) : ""; color: Util.alpha(Color.accent, 0.9); font.pixelSize: 8; font.bold: true }
                      Text { visible: modelData.m === "playlists" && svc; text: svc ? String(svc.playlists.length) : ""; color: Util.alpha(Color.accent, 0.9); font.pixelSize: 8; font.bold: true }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: root.setView(modelData.m) }
                  }
                }
                Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
                Comp.TransportButton { width: 30; height: 26; radius: 13; Layout.preferredWidth: 30; Layout.preferredHeight: 26; glyph: "↩"; glyphSize: 12; visible: root.viewMode === "library" && svc && !!svc.parentFilter; onClicked: { if (svc) svc.browseUp() } }
                Item {
                  id: kindDrop
                  visible: root.viewMode === "library"
                  Layout.preferredWidth: 150; Layout.preferredHeight: 26
                  Rectangle {
                    anchors.fill: parent
                    radius: 13
                    color: root.kindDropOpen ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.05)
                    border.width: 1; border.color: root.kindDropOpen ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.accent, 0.3)
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 9; spacing: 6
                      Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.filterLabel().toUpperCase(); color: root.kindDropOpen ? Color.accent : Util.alpha(Color.foreground, 0.75); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                      Text { text: "▾"; color: Util.alpha(Color.foreground, 0.55); font.pixelSize: 8 }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { kindPopup.opened ? kindPopup.close() : kindPopup.open() } }
                  }

                  // ============ BROWSE MENU (QQC.Popup — escapes clipping, closes on outside press) ============
                  Popup {
                    id: kindPopup
                    x: kindDrop.width - 190
                    y: kindDrop.height + 6
                    width: 190
                    padding: 0
                    modal: false
                    focus: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    onOpened: root.kindDropOpen = true
                    onClosed: root.kindDropOpen = false
                    background: Rectangle { radius: 12; color: Util.alpha(Color.background, 0.98); border.width: 1; border.color: Util.alpha(Color.accent, 0.35) }
                    contentItem: Column {
                      Rectangle { width: parent.width; height: 22; color: "transparent"
                        Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "BROWSE"; color: Util.alpha(Color.accent, 0.85); font.family: Style.font.family; font.pixelSize: 8; font.bold: true }
                      }
                      Repeater {
                        model: root.kindOptions()
                        delegate: Rectangle {
                          required property var modelData
                          width: 190; height: 30
                          color: optHover.containsMouse || modelData.value === (svc && svc.kind) ? Util.alpha(Color.accent, 0.12) : "transparent"
                          RowLayout { anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.label; color: modelData.value === (svc && svc.kind) ? Color.accent : Color.foreground; font.family: Style.font.family; font.pixelSize: 11; font.bold: modelData.value === (svc && svc.kind) }
                            Text { text: modelData.value === (svc && svc.kind) ? "✓" : ""; color: Color.accent; font.pixelSize: 10 }
                          }
                          MouseArea { id: optHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (svc) { svc.kind = modelData.value; svc.showQueue = false } kindPopup.close() } }
                        }
                      }
                    }
                  }

                  // ============ PLAYLIST PICKER (QQC.Popup — escapes clipping, closes on outside press) ============
                  Popup {
                    id: playlistPopup
                    x: kindDrop.width - 210
                    y: kindDrop.height + 6
                    width: 210
                    padding: 0
                    modal: false
                    focus: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    onClosed: root.playlistPickerTarget = null
                    background: Rectangle { radius: 12; color: Util.alpha(Color.background, 0.98); border.width: 1; border.color: Util.alpha(Color.accent, 0.3) }
                    contentItem: Column {
                      RowLayout { width: parent.width; spacing: 6
                        Text {
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                          text: "▤ ADD TO PLAYLIST" + (root.playlistPickerTarget ? " — “" + String(root.playlistPickerTarget.name || "") + "”" : "")
                          color: Util.alpha(Color.accent, 0.9); font.family: Style.font.family; font.pixelSize: 8; font.bold: true
                        }
                        Comp.TransportButton { Layout.preferredWidth: 22; Layout.preferredHeight: 22; glyph: "✕"; glyphSize: 9; onClicked: playlistPopup.close() }
                      }
                      Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.foreground, 0.08) }
                      Repeater {
                        model: (svc && svc.playlists) || []
                        delegate: Rectangle {
                          required property var modelData
                          property var pl: modelData
                          width: 210; height: 30
                          color: ph.containsMouse ? Util.alpha(Color.accent, 0.12) : "transparent"
                          RowLayout { anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: String(pl && pl.name || ""); color: Color.foreground; font.family: Style.font.family; font.pixelSize: 11 }
                            Text { text: String(pl && (pl.itemIds || []).length || 0); color: Util.alpha(Color.foreground, 0.45); font.family: Style.font.family; font.pixelSize: 9 }
                            Text { text: root.inPlaylist(pl, root.playlistPickerTarget) ? "✓" : ""; color: Color.accent; font.pixelSize: 10; font.bold: true }
                          }
                          MouseArea {
                            id: ph
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (svc && pl && root.playlistPickerTarget) { svc.addToPlaylist(String(pl.id), root.playlistPickerTarget); svc.statusText = "playlist “" + String(pl.name || "?") + "” + " + String(root.playlistPickerTarget.name || "") } playlistPopup.close() }
                          }
                        }
                      }
                      Rectangle { width: parent.width; height: 34; color: "transparent"; visible: !(svc && svc.playlists && svc.playlists.length)
                        Text { anchors.centerIn: parent; text: "no playlists yet — create one in PLAYLISTS"; color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 9 }
                      }
                    }
                  }
                }
                // search box (library browse mode)
                Rectangle {
                  visible: root.viewMode === "library"
                  Layout.preferredWidth: 150; Layout.preferredHeight: 26; radius: 13
                  color: Util.alpha(Color.foreground, 0.05); border.width: 1; border.color: Util.alpha(Color.accent, 0.25)
                  TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 10; anchors.rightMargin: 26
                    verticalAlignment: TextInput.AlignVCenter
                    color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10
                    // placeholder
                    Text {
                      anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                      visible: searchInput.text.length === 0
                      text: "search"
                      color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 10
                      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: searchInput.forceActiveFocus() }
                    }
                    onTextChanged: { if (svc) svc.query = text }
                  }
                  Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: searchInput.text !== ""; text: "✕"; color: Util.alpha(Color.foreground, 0.5); font.pixelSize: 10; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { searchInput.text = "" } } }
                }
              }

              // breadcrumb when drilling into a folder
              Text {
                Layout.fillWidth: true
                visible: root.viewMode === "library" && svc && !!svc.parentFilter
                text: "📍 " + root.parentPath() + " — " + root.libraryRows().length + " results (click ↩ to go up)"
                color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 8
              }

              // queue header
              RowLayout {
                Layout.fillWidth: true
                visible: root.viewMode === "queue"
                spacing: 6
                Text {
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: "📻 QUEUE — " + (svc ? svc.queue.length : 0) + " track(s)" + (svc && svc.queueIndex >= 0 && svc.queue[svc.queueIndex] ? " · now playing #" + (svc.queueIndex + 1) : " · nothing loaded")
                  color: Util.alpha(Color.accent, 0.75); font.family: Style.font.family; font.pixelSize: 8; font.bold: true
                }
                Comp.TransportButton { width: 64; height: 24; radius: 12; Layout.preferredWidth: 64; Layout.preferredHeight: 24; glyph: "✕"; label: "CLEAR"; glyphSize: 9; visible: svc && svc.queue.length > 0; onClicked: { if (svc) svc.clearQueue() } }
              }

              // playlists: create row (root level)
              RowLayout {
                Layout.fillWidth: true
                visible: root.viewMode === "playlists" && root.viewingPlaylistId === ""
                spacing: 6
                Text {
                  Layout.preferredWidth: 104
                  elide: Text.ElideRight
                  text: "▤ PLAYLISTS — " + (svc ? String(svc.playlists.length) : "0")
                  color: Util.alpha(Color.accent, 0.75); font.family: Style.font.family; font.pixelSize: 8; font.bold: true
                }
                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 26; radius: 13
                  color: Util.alpha(Color.foreground, 0.05); border.width: 1; border.color: Util.alpha(Color.accent, 0.25)
                  TextInput {
                    id: plNewInput
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10
                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; visible: plNewInput.text.length === 0; text: "new playlist name…"; color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 10; MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: plNewInput.forceActiveFocus() } }
                    text: root.pendingPlName || ""
                    onTextChanged: root.pendingPlName = text
                    Keys.onReturnPressed: root.createFromInput()
                    Keys.onEnterPressed: root.createFromInput()
                  }
                }
                Comp.TransportButton { width: 88; height: 26; radius: 13; Layout.preferredWidth: 88; Layout.preferredHeight: 26; glyph: "＋"; label: "CREATE"; glyphSize: 10; onClicked: root.createFromInput() }
              }

              // playlists: drilled-in header
              RowLayout {
                Layout.fillWidth: true
                visible: root.viewMode === "playlists" && root.viewingPlaylistId !== ""
                spacing: 6
                Comp.TransportButton { width: 30; height: 26; radius: 13; Layout.preferredWidth: 30; Layout.preferredHeight: 26; glyph: "↩"; glyphSize: 12; onClicked: root.viewingPlaylistId = "" }
                Text {
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: "▤ " + (svc && svc.playlistForId(root.viewingPlaylistId) ? String(svc.playlistForId(root.viewingPlaylistId).name || "") : "PLAYLIST") + " — " + String(svc ? svc.playlistCount(root.viewingPlaylistId) : 0) + " tracks"
                  color: Util.alpha(Color.accent, 0.75); font.family: Style.font.family; font.pixelSize: 8; font.bold: true
                }
                Comp.TransportButton { width: 88; height: 26; radius: 13; Layout.preferredWidth: 88; Layout.preferredHeight: 26; glyph: "▶"; label: "PLAY ALL"; glyphSize: 9; visible: svc && svc.playlistCount(root.viewingPlaylistId) > 0; onClicked: { if (svc) svc.playPlaylist(root.viewingPlaylistId) } }
              }

              // rows: media (library / queue / playlist items)
              ListView {
                id: libList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                visible: root.viewMode !== "playlists" || root.viewingPlaylistId !== ""
                model: root.viewMode === "queue" ? root.queueRows() : root.viewMode === "playlists" ? root.playlistItemRows() : root.libraryRows()
                delegate: Item {
                  required property var modelData
                  id: row
                  property var it: modelData.it || modelData
                  property int actionReserve: row.it && row.it.isFolder ? 6 : 180
                  width: ListView.view.width - 4
                  height: 54
                  Rectangle {
                    id: rowBg
                    anchors.fill: parent
                    radius: 11
                    color: rowMouse.containsMouse ? Util.alpha(Color.foreground, 0.09) : (modelData.cur ? Util.alpha(Color.accent, 0.14) : Util.alpha(Color.foreground, 0.04))
                    border.width: 1
                    border.color: rowMouse.containsMouse ? Util.alpha(Color.accent, 0.55) : (modelData.cur ? Util.alpha(Color.accent, 0.35) : Util.alpha(Color.foreground, 0.07))
                    RowLayout {
                      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: 8; anchors.rightMargin: 8
                      spacing: 8
                      Rectangle {
                        Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: 8
                        color: Util.alpha(Color.accent, 0.1); border.width: 1; border.color: Util.alpha(Color.accent, 0.22); clip: true
                        Image {
                          anchors.fill: parent
                          source: svc && row.it ? svc.imageUrl(row.it, 40) : ""
                          fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                          visible: source !== ""
                          onStatusChanged: if (status === Image.Error) visible = false
                        }
                        Text { anchors.centerIn: parent; visible: !(row.it && row.it.imageTag); text: row.it ? String(row.it.name||"?").slice(0,1).toUpperCase() : "♪"; color: Color.accent; font.family: Style.font.family; font.pixelSize: 14; font.bold: true }
                      }
                      Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { width: parent.width; text: row.it ? String(row.it.name||"") : ""; color: modelData.cur ? Color.accent : Color.foreground; font.family: Style.font.family; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: row.it ? (String(row.it.type||"") + (row.it.artist ? " · " + row.it.artist : "") + (row.it.album ? " · " + row.it.album : "") + (row.it.year ? " · " + row.it.year : "")).trim() : ""; color: Util.alpha(Color.foreground, 0.55); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
                      }
                      Text { text: row.it && row.it.runtimeMs ? T.formatMs(row.it.runtimeMs) : ""; color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                      Text { text: modelData.cur ? "▶" : "›"; color: modelData.cur ? Color.accent : Util.alpha(Color.accent, 0.55); font.family: Style.font.family; font.pixelSize: 14 }
                      Item { Layout.preferredWidth: row.actionReserve }
                    }
                    MouseArea {
                      id: rowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { if (svc) { console.log("finamp click id=" + String(row.it && row.it.id) + " name=" + String(row.it && row.it.name)); svc.playItem(row.it) } }
                    }
                    Row {
                      id: rowActions
                      anchors.right: parent.right
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 6
                      z: 5
                      Comp.TransportButton { width: 26; height: 26; glyph: svc && svc.isDownloaded(row.it) ? "⤓✓" : (svc && svc.downloading && String(svc.pendingDownloadId) === String(row.it && row.it.id) ? "…" : "⤓"); glyphSize: 10; selected: svc && svc.isDownloaded(row.it); visible: !(row.it && row.it.isFolder); onClicked: { if (svc && row.it) svc.isDownloaded(row.it) ? svc.offload(row.it) : svc.download(row.it) } }
                      Comp.TransportButton { width: 26; height: 26; glyph: "▶"; glyphSize: 9; visible: !(row.it && row.it.isFolder) && !(modelData.cur || (svc && svc.current && String(svc.current.id) === String(row.it.id))); onClicked: { if (svc) svc.playItem(row.it) } }
                      Comp.TransportButton { width: 26; height: 26; glyph: "⧉"; glyphSize: 10; visible: !(row.it && row.it.isFolder) && root.viewMode !== "queue"; onClicked: { if (svc) svc.enqueue(row.it) } }
                      Comp.TransportButton { width: 48; height: 26; glyph: "▤"; glyphSize: 10; visible: !(row.it && row.it.isFolder) && root.viewMode === "library"; onClicked: { if (kindPopup.opened) kindPopup.close(); root.playlistPickerTarget = row.it; playlistPopup.open() } }
                      Comp.TransportButton { width: 26; height: 26; glyph: "✕"; glyphSize: 10; selected: root.viewMode === "queue" || root.inQueue(row.it) || root.viewMode === "playlists"; visible: !(row.it && row.it.isFolder) && (root.inQueue(row.it) || root.viewMode === "queue" || (root.viewMode === "playlists" && root.viewingPlaylistId !== "")); onClicked: { if (root.viewMode === "playlists" && root.viewingPlaylistId !== "") { if (svc) svc.removeFromPlaylist(root.viewingPlaylistId, row.it); if (svc) svc.statusText = "removed from playlist: " + String(row.it.name || "") } else { if (svc) svc.removeFromQueue(row.it.id); if (svc) svc.statusText = "removed from queue: " + String(row.it.name || "") } } }
                    }
                  }
                }
              }

              // rows: playlist list (root level)
              ListView {
                id: playlistList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                visible: root.viewMode === "playlists" && root.viewingPlaylistId === ""
                model: root.playlistRows()
                delegate: Rectangle {
                  required property var modelData
                  property var pl: modelData.playlist
                  width: ListView.view.width - 4
                  height: 46
                  radius: 11
                  color: mHover.containsMouse ? Util.alpha(Color.foreground, 0.09) : (svc && svc.activePlaylistId === String(pl && pl.id) ? Util.alpha(Color.accent, 0.14) : Util.alpha(Color.foreground, 0.04))
                  border.width: 1
                  border.color: mHover.containsMouse ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.accent, 0.3)
                  MouseArea {
                    id: mHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (svc && pl) { svc.activePlaylistId = String(pl.id); root.viewingPlaylistId = String(pl.id) } }
                  }
                  RowLayout {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12; anchors.rightMargin: 8
                    spacing: 8
                    Text { text: "▤"; color: Color.accent; font.pixelSize: 13 }
                    Column {
                      Layout.fillWidth: true
                      spacing: 1
                      Text { width: parent.width; elide: Text.ElideRight; text: pl && String(pl.name || ""); color: Color.foreground; font.family: Style.font.family; font.pixelSize: 12; font.bold: true }
                      Text { width: parent.width; elide: Text.ElideRight; text: (pl && pl.itemIds ? pl.itemIds.length : 0) + " track(s)" + (svc && svc.activePlaylistId === String(pl && pl.id) ? " · active" : ""); color: Util.alpha(Color.foreground, 0.55); font.family: Style.font.family; font.pixelSize: 9 }
                    }
                    Comp.TransportButton { width: 26; height: 26; glyph: "▶"; glyphSize: 9; visible: pl && (pl.itemIds || []).length > 0; onClicked: { if (svc) svc.playPlaylist(pl.id) } }
                    Comp.TransportButton { width: 26; height: 26; glyph: "❤"; glyphSize: 10; selected: svc && svc.activePlaylistId === String(pl && pl.id); onClicked: { if (svc && pl) { svc.activePlaylistId = String(pl.id); svc.statusText = "playlist: " + String(pl.name || "") } } }
                    Comp.TransportButton { width: 26; height: 26; glyph: "🗑"; glyphSize: 10; onClicked: { if (svc && pl) svc.removePlaylist(pl.id) } }
                  }
                }
              }
            }
          }
        }

      }

      // ================= SETTINGS OVERLAY =================
      Rectangle {
        id: settingsOverlay
        anchors.fill: parent
        radius: 22
        color: Util.alpha(Color.background, 0.97)
        visible: root.settingsOpen
        z: 30
MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
          anchors.centerIn: parent
          width: Math.min(parent.width - 80, 620)
          spacing: 12

          RowLayout { Layout.fillWidth: true; spacing: 8
            Text { Layout.fillWidth: true; text: "SERVER SETTINGS"; color: Color.accent; font.family: Style.font.family; font.pixelSize: 14; font.bold: true }
            Comp.TransportButton { Layout.preferredWidth: 28; Layout.preferredHeight: 28; glyph: "✕"; glyphSize: 11; onClicked: root.closeSettings() }
          }

          Text { Layout.fillWidth: true; text: "Point Finamp at a Jellyfin/Plex server on your tailnet, then add an API key (Jellyfin Dashboard → API Keys) or user id."; color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 10; wrapMode: Text.WordWrap }

          // discover
          RowLayout { Layout.fillWidth: true; spacing: 8
            Comp.TransportButton { Layout.preferredWidth: 120; Layout.preferredHeight: 32; radius: 16; glyph: "📡"; label: "DISCOVER"; glyphSize: 12; onClicked: root.discoverNow() }
            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: (svc && svc.discovered.length ? svc.discovered.length + " found — click one to connect" : "probing tailscale…"); color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 9 }
          }
          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
              model: svc ? svc.discovered : []
              delegate: Rectangle {
                required property var modelData
                Layout.preferredHeight: 40
                Layout.preferredWidth: dTxt.implicitWidth + 22
                radius: 10
                color: Util.alpha(Color.accent, 0.09); border.width: 1; border.color: Util.alpha(Color.accent, 0.3)
                Text { id: dTxt; anchors.centerIn: parent; text: (modelData.name || modelData.host) + " · " + modelData.type + " · " + modelData.port; color: Util.alpha(Color.foreground, 0.85); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.applyDiscovered(modelData) }
              }
            }
          }

          Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, 0.08) }

          Text { text: "Server URL (http://<host>.tail*****.ts.net:8096)"; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
          RowLayout { Layout.fillWidth: true; spacing: 8
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 32; radius: 12; color: Util.alpha(Color.foreground, 0.05); border.width: 1; border.color: Util.alpha(Color.foreground, 0.15); TextInput { id: serverInput; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10 } }
            Comp.TransportButton { Layout.preferredWidth: 64; Layout.preferredHeight: 30; radius: 15; label: "SAVE"; glyph: "✓"; glyphSize: 10; onClicked: root.saveServer() }
          }

          Text { text: "API key (Jellyfin Dashboard → API Keys)"; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
          RowLayout { Layout.fillWidth: true; spacing: 8
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 32; radius: 12; color: Util.alpha(Color.foreground, 0.05); border.width: 1; border.color: Util.alpha(Color.foreground, 0.15); TextInput { id: apiInput; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10; echoMode: TextInput.Password } }
            Comp.TransportButton { Layout.preferredWidth: 64; Layout.preferredHeight: 30; radius: 15; label: "SAVE"; glyph: "✓"; glyphSize: 10; onClicked: root.saveApiKey() }
          }

          Text { text: "User ID (optional — auto-resolved)"; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
          RowLayout { Layout.fillWidth: true; spacing: 8
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 32; radius: 12; color: Util.alpha(Color.foreground, 0.05); border.width: 1; border.color: Util.alpha(Color.foreground, 0.15); TextInput { id: userInput; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10 } }
            Comp.TransportButton { Layout.preferredWidth: 64; Layout.preferredHeight: 30; radius: 15; label: "SAVE"; glyph: "✓"; glyphSize: 10; onClicked: root.saveUserId() }
          }

          RowLayout { Layout.fillWidth: true; spacing: 8
            Comp.TransportButton { Layout.preferredWidth: 110; Layout.preferredHeight: 30; radius: 15; label: "OPEN WEB"; glyph: "🌐"; glyphSize: 10; onClicked: { if (svc) svc.openWeb() } }
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "serverUrl, apiKey and userId are stored in ~/.config/omarchy/shell.json (plaintext, chmod 600 via atomic write). Only http(s) tailscale hosts allowed."; color: Util.alpha(Color.foreground, 0.35); font.family: Style.font.family; font.pixelSize: 8 }
          }
        }
      }
    }

Component.onCompleted: console.log("finamp Dash: ready=" + ready)

  QtObject {
    id: sliderBar
    property color foreground: Color.accent
    property color background: Color.background
  }
  }

  property var eqBands: [0,0,0,0,0,0,0,0,0,0]
  function applyDiscovered(s) { if (svc) svc.applyServer(s) }
}