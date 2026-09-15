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
  property bool plOpen: false
  property string pendingPlName: ""
  property bool seekDrag: false
  property real volume: 1.0
  property real speed: 1.0
  readonly property bool isVideo: media.hasVideo
  readonly property bool hasCurrent: svc && svc.current !== null
  property bool kindDropOpen: false

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
    var out = []
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (!it) continue
      if (k !== "all" && String(it.type) !== k) continue
      if (par && String(it.parentId) !== par) continue
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
    root.plOpen = true
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

MouseArea { anchors.fill: parent; onClicked: { root.plOpen = false; root.kindDropOpen = false } }

      Rectangle {
        anchors.fill: parent; radius: 22; clip: true; color: "transparent"
        focus: root.dashVisible
        Keys.onSpacePressed: { event.accepted = true; root.playPause() }
        Keys.onLeftPressed: { event.accepted = true; root.seekBy(-5000) }
        Keys.onRightPressed: { event.accepted = true; root.seekBy(5000) }
        Keys.onUpPressed: { event.accepted = true; root.volBy(0.05) }
        Keys.onDownPressed: { event.accepted = true; root.volBy(-0.05) }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_L) { event.accepted = true; if (svc) svc.showQueue = !svc.showQueue }
          else if (event.key === Qt.Key_M) { event.accepted = true; root.volume = root.volume > 0 ? 0 : 1.0 }
          else if (event.key === Qt.Key_Escape) { event.accepted = true; root.kindDropOpen = false; root.settingsOpen = false }
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
                Comp.TransportButton { Layout.preferredWidth: 74; Layout.preferredHeight: 34; radius: 17; glyph: svc && svc.current && svc.isDownloaded(svc.current) ? "✓" : "⤓"; label: svc && svc.current && svc.isDownloaded(svc.current) ? "OFFLOAD" : "SAVE"; glyphSize: 12; selected: svc && svc.current && svc.isDownloaded(svc.current); onClicked: { if (svc && svc.current) svc.isDownloaded(svc.current) ? svc.offload(svc.current) : svc.download(svc.current) } }
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

              // filter dropdown + up + search + queue toggle
              RowLayout {
                Layout.fillWidth: true
                spacing: 6
                z: 3
                Comp.TransportButton { width: 30; height: 26; radius: 13; Layout.preferredWidth: 30; Layout.preferredHeight: 26; glyph: "↩"; glyphSize: 12; visible: svc && !!svc.parentFilter; onClicked: { if (svc) { svc.parentFilter = ""; svc.showQueue = false } } }
                Item {
                  id: kindDrop
                  Layout.preferredWidth: 132; Layout.preferredHeight: 26
                  Rectangle {
                    anchors.fill: parent
                    radius: 13
                    color: root.kindDropOpen ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.05)
                    border.width: 1; border.color: root.kindDropOpen ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.accent, 0.3)
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 9; spacing: 6
                      Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.filterLabel().toUpperCase(); color: root.kindDropOpen ? Color.accent : Util.alpha(Color.foreground, 0.75); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                      Text { text: "▾"; color: Util.alpha(Color.foreground, 0.55); font.pixelSize: 8 }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: root.kindDropOpen = !root.kindDropOpen }
                  }
                  Rectangle {
                    y: parent.height + 4
                    width: 170
                    visible: root.kindDropOpen
                    z: 30
                    radius: 12
                    color: Util.alpha(Color.background, 0.98)
                    border.width: 1; border.color: Util.alpha(Color.foreground, 0.16)
                    layer.enabled: true
                    Column {
                      Repeater {
                        model: root.kindOptions()
                        delegate: Rectangle {
                          required property var modelData
                          width: 170; height: 30
                          color: optHover.containsMouse || modelData.value === (svc && svc.kind) ? Util.alpha(Color.accent, 0.12) : "transparent"
                          RowLayout { anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.label; color: modelData.value === (svc && svc.kind) ? Color.accent : Color.foreground; font.family: Style.font.family; font.pixelSize: 11; font.bold: modelData.value === (svc && svc.kind) }
                            Text { text: modelData.value === (svc && svc.kind) ? "✓" : ""; color: Color.accent; font.pixelSize: 10 }
                          }
                          MouseArea { id: optHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (svc) { svc.kind = modelData.value; svc.showQueue = false } root.kindDropOpen = false; root.plOpen = false } }
                        }
                      }
                    }
                  }
                }
// playlist picker pill + menu
                Item {
                  id: plWrap
                  Layout.preferredWidth: 150; Layout.preferredHeight: 26
                  z: 40
                  Rectangle {
                    id: plPill
                    anchors.fill: parent
                    radius: 13
                    color: root.plOpen ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.05)
                    border.width: 1; border.color: root.plOpen ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.accent, 0.3)
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                      Text { Layout.fillWidth: true; elide: Text.ElideRight; text: "▤ " + (root.playlistName() || "PLAYLISTS"); color: root.plOpen ? Color.accent : Util.alpha(Color.foreground, 0.75); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                      Text { text: "▾"; color: Util.alpha(Color.foreground, 0.55); font.pixelSize: 8 }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: root.plOpen = !root.plOpen }
                  }
                  Rectangle {
                    id: plMenu
                    visible: root.plOpen
                    anchors.top: parent.bottom
                    anchors.topMargin: 6
                    anchors.left: parent.left
                    width: 230
                    z: 41
                    radius: 12
                    color: Util.alpha(Color.background, 0.98)
                    border.width: 1; border.color: Util.alpha(Color.accent, 0.25)
                    layer.enabled: true
                    Column {
                      width: parent.width
                      spacing: 2
                      Rectangle { width: parent.width; height: 30; color: Util.alpha(Color.accent, 0.1); border.width: 1; border.color: Util.alpha(Color.foreground, 0.12)
                        RowLayout { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 6; spacing: 6
                          TextInput { id: plNewInput; Layout.fillWidth: true; Layout.preferredHeight: 30; verticalAlignment: TextInput.AlignVCenter; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10; text: root.pendingPlName || ""; onTextChanged: root.pendingPlName = text; Keys.onReturnPressed: root.createFromInput(); Keys.onEnterPressed: root.createFromInput() }
                          Comp.TransportButton { width: 24; height: 24; glyph: "✓"; glyphSize: 9; onClicked: root.createFromInput() }
                        }
                      }
                      Repeater {
                        model: (svc && svc.playlists) || []
                        delegate: RowLayout {
                          required property var modelData
                          property var pl: modelData
                          Layout.fillWidth: true
                          Layout.preferredHeight: 30
                          spacing: 2
                          Item { Layout.preferredWidth: 10; Layout.preferredHeight: 1 }
                          Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: String((pl && pl.name) || "")
                            color: svc && svc.activePlaylistId === String(pl && pl.id) ? Color.accent : Util.alpha(Color.foreground, 0.78)
                            font.family: Style.font.family; font.pixelSize: 10; font.bold: svc && svc.activePlaylistId === String(pl && pl.id)
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: { if (svc && pl) { svc.activePlaylistId = String(pl.id); svc.statusText = "playlist: " + String(pl.name || "") } root.plOpen = false } }
                          }
                          Text { Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight; text: String((pl && pl.itemIds) ? pl.itemIds.length : 0); color: Util.alpha(Color.foreground, 0.45); font.family: Style.font.family; font.pixelSize: 8 }
                          Comp.TransportButton { Layout.preferredWidth: 22; Layout.preferredHeight: 22; glyph: "▶"; glyphSize: 8; visible: pl && (pl.itemIds || []).length > 0; onClicked: { if (svc) svc.playPlaylist(pl.id); root.plOpen = false } }
                          Comp.TransportButton { Layout.preferredWidth: 22; Layout.preferredHeight: 22; glyph: "🗑"; glyphSize: 9; onClicked: { if (svc && pl) svc.removePlaylist(pl.id); root.plOpen = false } }
                          Item { Layout.preferredWidth: 4; Layout.preferredHeight: 1 }
                        }
                      }
                    }
                  }
                }
               Rectangle {
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
                Rectangle {
                  Layout.preferredWidth: 92; Layout.preferredHeight: 26; radius: 13
                  color: svc && svc.showQueue ? Util.alpha(Color.accent, 0.2) : Util.alpha(Color.foreground, 0.05)
                  border.width: 1; border.color: Util.alpha(Color.accent, 0.45)
                  RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 4
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: "QUEUE " + (svc ? svc.queue.length : 0); color: svc && svc.showQueue ? Color.accent : Util.alpha(Color.foreground, 0.7); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                    Text { text: "✕"; visible: svc && svc.showQueue && svc.queue.length > 0; color: Color.urgent; font.pixelSize: 10; font.bold: true; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (svc) svc.clearQueue() } } }
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (svc) svc.showQueue = !svc.showQueue } }
                }
              }

              // breadcrumb when drilling into a folder
              Text {
                Layout.fillWidth: true
                visible: svc && !!svc.parentFilter
                text: "📍 " + root.parentName() + " — " + root.libraryRows().length + " results (click ↩ to go up)"
                color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 8
              }

              // queue header
              Text {
                Layout.fillWidth: true
                visible: svc && svc.showQueue
                text: "📻 QUEUE — " + (svc ? svc.queue.length : 0) + " track(s)" + (svc && svc.queueIndex >= 0 && svc.queue[svc.queueIndex] ? " · now playing #" + (svc.queueIndex + 1) : " · nothing loaded")
                color: Util.alpha(Color.accent, 0.7); font.family: Style.font.family; font.pixelSize: 8; font.bold: true
              }

              // rows
              ListView {
                id: libList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: svc && svc.showQueue ? root.queueRows() : root.libraryRows()
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
                      Comp.TransportButton { width: 26; height: 26; glyph: svc && svc.isDownloaded(row.it) ? "⤓✓" : "⤓"; glyphSize: 10; selected: svc && svc.isDownloaded(row.it); visible: !(row.it && row.it.isFolder); onClicked: { if (svc) svc.download(row.it) } }
                      Comp.TransportButton { width: 26; height: 26; glyph: "▶"; glyphSize: 9; visible: !(row.it && row.it.isFolder) && !(modelData.cur || (svc && svc.current && String(svc.current.id) === String(row.it.id))); onClicked: { if (svc) svc.playItem(row.it) } }
                      Comp.TransportButton { width: 26; height: 26; glyph: "⧉"; glyphSize: 10; visible: !(row.it && row.it.isFolder); onClicked: { if (svc) svc.enqueue(row.it) } }
                      Comp.TransportButton { width: 48; height: 26; glyph: "▤"; glyphSize: 10; label: root.pendingPlaylistId === (row.it && String(row.it.id)) ? "✓" : ""; visible: !(row.it && row.it.isFolder); onClicked: { if (svc) svc.togglePlaylistPill(row.it) } }
                      Comp.TransportButton { width: 26; height: 26; glyph: "✕"; glyphSize: 10; selected: root.inQueue(row.it); visible: !(row.it && row.it.isFolder) && root.inQueue(row.it); onClicked: { if (svc) svc.removeFromQueue(row.it.id); if (svc) svc.statusText = "removed from queue: " + String(row.it.name || "") } }
                    }
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