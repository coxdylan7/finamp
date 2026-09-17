import QtQuick
import Quickshell
import Quickshell.Io
import "FinAmp.js" as T

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "djc.finamp"
  readonly property var pluginEntry: T.pluginEntry(shell && shell.shellConfig ? shell : (fileConfig ? { shellConfig: fileConfig } : null), pluginId)

  // ---- config ----
  readonly property string serverUrl: T.configStr(pluginEntry, "serverUrl", "")
  readonly property string apiKey: T.configStr(pluginEntry, "apiKey", "")
  readonly property string userId: T.configStr(pluginEntry, "userId", "")
  readonly property string plexToken: T.configStr(pluginEntry, "plexToken", "")
  readonly property string clientId: T.configStr(pluginEntry, "clientId", "")
  readonly property string libraryOnly: T.configStr(pluginEntry, "libraryOnly", "music")
  property string serverName: ""
  property string serverVersion: ""
  property string serverId: ""
  property string serverType: "jellyfin"
  property bool wizardPending: false

  readonly property string homeDir: Quickshell.env("HOME") || "~"
  readonly property string cacheDir: homeDir + "/.cache/omarchy/finamp"
  readonly property string cacheMedia: cacheDir + "/media.json"
  readonly property string cacheBrowse: cacheDir + "/browse.json"
  readonly property string cacheProbe: cacheDir + "/discovery.json"
  readonly property string shellJson: homeDir + "/.config/omarchy/shell.json"

  readonly property string helperProbe: { var u=Qt.resolvedUrl("./helpers/probe-server.py"); var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperMedia: { var u=Qt.resolvedUrl("./helpers/fetch-media.py"); var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperWrite: { var u=Qt.resolvedUrl("./helpers/write-config.py"); var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperDownloads: { var u=Qt.resolvedUrl("./helpers/downloads-manager.py"); var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string downloadsPath: homeDir + "/.cache/omarchy/finamp/downloads.json"
  readonly property string helperPlaylists: { var u=Qt.resolvedUrl("./helpers/finamp-playlists.py"); var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string playlistsPath: homeDir + "/.cache/omarchy/finamp/playlists.json"

  FileView {
    id: shellConfigFile
    path: homeDir + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
  }
  property var fileConfig: {
    try { var t=shellConfigFile.text(); return t ? JSON.parse(t) : null } catch(e){ return null }
  }

  FileView {
    id: cacheMediaFile
    path: homeDir + "/.cache/omarchy/finamp/media.json"
    watchChanges: false
    printErrors: false
    onTextChanged: root.hydrateCache()
  }

  // ---- library + connection state ----
  property var dataViews: []
  property var dataItems: []
  property var discovered: []
  property bool mediaOk: false
  property string mediaError: ""
  property string statusText: "finamp — server not configured; hit Discover or fill in Settings"
  property int refreshTick: 0
  property int uiTick: 0          // bumped whenever the row list must re-render (kind/query/year/dataItems)

  property string query: ""
  property string kind: "all"        // all | Movie | Series | Episode | MusicAlbum | Audio | Video | year
  property int year: 0               // ProductionYear filter (client-side, set when browsing a year)
  property string genre: ""             // Genre filter (client-side, set when browsing a genre)
  property string viewId: ""         // present when drilling into a folder/library
  property string parentFilter: ""   // ParentId filter (folder drill)
  property bool showQueue: false
  property var continuation: []   // library continuation (auto) tracks — queued AFTER the user's queue

  // ---- playback / queue ----
  property string phase: "stopped"   // stopped | playing | paused | ended
  property var queue: []
  property int queueIndex: -1
  property var current: null
  property bool shuffle: false
  property bool repeat: false
  property string spectrumMode: "bars"   // bars | wave | circle | none — visualizer mode

  // --- up-next preview ---
  // Play-order lists that drive both the "next 10" preview and auto-playback.
  // Recomputed when the library or shuffle toggle changes; the stream walks once
  // through the whole list per pass so a shuffled pass never repeats tracks.
  property var libraryOrder: []   // playable audio, album/track order (no shuffle)
  property var shuffleOrder: []   // playable audio, randomized (shuffle on)
  property var playOrder: []      // the active stream (libraryOrder or shuffleOrder)
  property int feedPos: 0         // index into playOrder where continuation picks up next
  property var playedSet: ({})    // ids already pulled into the stream this pass
  function buildOrders() {
    var pool = []
    for (var i = 0; i < root.dataItems.length; i++) {
      var it = root.dataItems[i]
      if (it && !it.isFolder && (it.mediaType === "Audio" || it.type === "Audio")) pool.push(it)
    }
    root.libraryOrder = pool.slice()
    root.libraryOrder.sort(function(a, b) {
      var c = String(a.album || "").localeCompare(String(b.album || ""))
      if (c !== 0) return c
      c = (a.index || 0) - (b.index || 0)
      if (c !== 0) return c
      return String(a.name || "").localeCompare(String(b.name || ""))
    })
    root.shuffleOrder = pool.slice()
    for (var s = root.shuffleOrder.length - 1; s > 0; s--) {
      var r = Math.floor(Math.random() * (s + 1))
      var tmp = root.shuffleOrder[s]
      root.shuffleOrder[s] = root.shuffleOrder[r]
      root.shuffleOrder[r] = tmp
    }
    root.playOrder = root.shuffle ? root.shuffleOrder : root.libraryOrder
    root.feedPos = 0
    root.playedSet = {}
    root.continuation = []
  }
  // What actually plays next, as a fixed-size always-N preview:
  // the user's queue overrides the library stream and fills the front, the rest
  // comes from the continuous library stream (album order, or random if shuffled)
  // which never repeats a track within a pass.
  function upNext(n) {
    var limit = Math.max(1, n || 10)
    if (root.continuation.length < limit) root.appendLibraryBatch()
    var out = []
    var have = {}
    if (root.current) have[String(root.current.id)] = 1
    var start = root.queueIndex >= 0 ? root.queueIndex + 1 : 0
    for (var m = start; m < root.queue.length && out.length < limit; m++) {
      var q = root.queue[m]
      if (!q || have[String(q.id)]) continue
      have[String(q.id)] = 1
      out.push(q)
    }
    for (var c = 0; c < root.continuation.length && out.length < limit; c++) {
      var cc = root.continuation[c]
      if (!cc || have[String(cc.id)]) continue
      have[String(cc.id)] = 1
      out.push(cc)
    }
    return out
  }
  function toggleShuffle() {
    root.shuffle = !root.shuffle
    root.buildOrders()
    // keep the stream anchored after the track currently playing
    if (root.current) {
      var order = root.playOrder
      for (var k = 0; k < order.length; k++) {
        if (String(order[k].id) === String(root.current.id)) { root.feedPos = (k + 1) % order.length; break }
      }
    }
    root.continuation = []
    root.uiTick++
    console.log("finamp: shuffle " + (root.shuffle ? "on" : "off"))
  }

  function toggleDash() { root.dashVisible = !root.dashVisible; console.log("finamp: dash " + (root.dashVisible ? "open" : "close")) }
  property bool dashVisible: false

  function streamUrl(rec, transcode) { if (!rec) return ""; return T.jellyfinStreamUrl(root.serverUrl, rec, root.apiKey, transcode) }
  function imageUrl(rec, w) { if (!rec || !rec.id) return ""; return T.jellyfinImageUrl(root.serverUrl, rec.id, rec.imageTag, root.apiKey, w || 300) }
  function downloadUrl(rec) { if (!rec) return ""; return T.jellyfinDownloadUrl(root.serverUrl, rec.id, root.apiKey) }

  function queueIndexForId(id) { for (var i=0;i<root.queue.length;i++){ if (root.queue[i] && String(root.queue[i].id) === String(id)) return i } return -1 }

  function playItem(rec) {
    if (!rec) return
    if (rec.isFolder) { root.browseFolder(rec.id); return }
    var startingFresh = !root.current || root.phase === "stopped"
    var idx = root.queueIndexForId(rec.id)
    if (idx < 0) { root.queue = root.queue.concat([rec]); idx = root.queue.length - 1 }
    root.queueIndex = idx
    root.current = rec
    root.phase = "playing"
    root.uiTick++
    if (startingFresh) {
      // align the stream so "next 10" continues right after the picked track
      root.buildOrders()
      var order = root.playOrder
      for (var k = 0; k < order.length; k++) {
        if (String(order[k].id) === String(rec.id)) { root.feedPos = (k + 1) % order.length; break }
      }
      root.playedSet = {}
      root.continuation = []
    }
    root.appendLibraryBatch()
    console.log("finamp: play " + String(rec.name || rec.id))
  }
  function browseFolder(id) {
    root.parentFilter = String(id || "")
    root.viewId = ""
    root.showQueue = false
    root.statusText = "Browsing folder…"
    root.tick()
    root.fetchMedia(null, null, root.parentFilter)
  }
  function browseUp() {
    root.parentFilter = ""
    root.year = 0
    root.genre = ""
    root.statusText = "back to library…"
    root.tick()
    root.fetchMedia()
  }
  function randomLibraryPick() {
    var pool = []
    for (var i = 0; i < root.dataItems.length; i++) {
      var it = root.dataItems[i]
      if (it && !it.isFolder && (it.mediaType === "Audio" || it.type === "Audio")) pool.push(it)
    }
    if (!pool.length) return null
    var pick = pool[Math.floor(Math.random() * pool.length)]
    if (root.current && pool.length > 1 && String(pick.id) === String(root.current.id)) {
      pick = pool[Math.floor(Math.random() * pool.length)]
    }
    return pick
  }
// Keep the continuation topped up to `target` (max 10) by walking playOrder
// forward from feedPos, never pulling the same track twice within a pass. When
// one whole pass is consumed it rotates to a fresh one (re-rolling shuffle) so
// the next-10 window never shrinks.
  function appendLibraryBatch() {
    var order = root.playOrder
    if (!order || !order.length) return false
    var n = order.length
    var target = Math.min(10, n)
    if (root.continuation.length >= target) return true
    var attempt = 0
    while (root.continuation.length < target && attempt < 2) {
      attempt++
      var have = {}
      if (root.current) have[String(root.current.id)] = 1
      var scan = root.queue.concat(root.continuation)
      for (var i = 0; i < scan.length; i++) if (scan[i]) have[String(scan[i].id)] = 1
      var guard = 0
      while (root.continuation.length < target && guard < n * 2) {
        guard++
        var it = order[root.feedPos % n]
        root.feedPos = (root.feedPos + 1) % n
        if (!it || have[String(it.id)] || root.playedSet[String(it.id)]) continue
        root.continuation.push(it)
        root.playedSet[String(it.id)] = 1
      }
      if (root.continuation.length >= target) break
      // current pass exhausted — rotate to a fresh one and retry once
      root.playedSet = {}
      root.feedPos = 0
      if (root.shuffle) {
        var pool = root.libraryOrder.slice()
        for (var s = pool.length - 1; s > 0; s--) {
          var r = Math.floor(Math.random() * (s + 1))
          var tmp = pool[s]; pool[s] = pool[r]; pool[r] = tmp
        }
        root.shuffleOrder = pool
        root.playOrder = pool
        order = pool
      }
    }
    if (root.continuation.length) { root.uiTick++; return true }
    return false
  }
  function playNext() {
    // finish the current queued item — consume it so the queue never replays itself
    if (root.queueIndex >= 0 && root.queue.length) {
      var played = root.queueIndex
      if (root.repeat && root.queue.length <= 1) {
        var rep = root.queue[played]
        root.phase = "stopped"
        Qt.callLater(function() { root.current = Object.assign({}, rep); root.phase = "playing" })
        return
      }
      root.queue = root.queue.slice(0, played).concat(root.queue.slice(played + 1))
      root.queueIndex = -1
      root.uiTick++
    }
    if (root.queue.length) {
      // the user's queue always plays first
      var i = root.shuffle && root.queue.length > 1 ? Math.floor(Math.random() * root.queue.length) : 0
      root.queueIndex = i
      root.current = root.queue[i]
      root.phase = "playing"
      root.uiTick++
      return
    }
    // user queue consumed → play the library continuation stream
    if (root.continuation.length < 10) root.appendLibraryBatch()
    if (!root.continuation.length) root.appendLibraryBatch()   // pass just reset — kick off fresh one
    if (root.continuation.length) {
      root.current = root.continuation[0]
      root.continuation = root.continuation.slice(1)
      root.queueIndex = -1
      root.phase = "playing"
      root.uiTick++
      root.appendLibraryBatch()   // refill so the next-10 stream never drains
      return
    }
    // nothing at all to play
    var pick = root.randomLibraryPick()
    if (!pick) { root.phase = "stopped"; return }
    root.queueIndex = -1
    root.current = pick
    root.phase = "playing"
    root.uiTick++
    console.log("finamp: queue done — continuing from library with " + String(pick.name || pick.id))
  }
  function playPrev() {
    if (!root.queue.length) return
    var i = root.queueIndex - 1
    if (i < 0) i = root.queue.length - 1
    root.queueIndex = i
    root.current = root.queue[i]
    root.phase = "playing"
  }
  function playRandom() {
    var pool = []
    for (var i = 0; i < root.dataItems.length; i++) {
      var it = root.dataItems[i]
      if (it && !it.isFolder) pool.push(it)
    }
    if (!pool.length) { root.statusText = "no playable tracks"; return }
    var pick = pool[Math.floor(Math.random() * pool.length)]
    console.log("finamp: random play " + String(pick.name || pick.id))
    root.playItem(pick)
  }
  function togglePlay() {
    if (root.current) { root.toggleRow(root.current); return }
    root.playRandom()
  }
  function removeFromQueue(id) {
    for (var i = 0; i < root.queue.length; i++) {
      if (root.queue[i] && String(root.queue[i].id) === String(id)) {
        var nq = root.queue.slice()
        nq.splice(i, 1)
        root.queue = nq
        root.uiTick++
        if (root.current && String(root.current.id) === String(id)) { root.current = null; root.queueIndex = -1; root.phase = "stopped" }
        else if (i < root.queueIndex) root.queueIndex = root.queueIndex - 1
        else if (i === root.queueIndex) root.queueIndex = -1
        break
      }
    }
    for (var ci = 0; ci < root.continuation.length; ci++) {
      if (root.continuation[ci] && String(root.continuation[ci].id) === String(id)) {
        var nc = root.continuation.slice()
        nc.splice(ci, 1)
        root.continuation = nc
        root.uiTick++
        break
      }
    }
  }
  function toggleRow(rec) {
    if (!rec || rec.isFolder) { root.playItem(rec); return }
    if (root.current && String(root.current.id) === String(rec.id)) {
      if (root.phase === "playing") root.phase = "paused"
      else root.phase = "playing"
      return
    }
    root.playItem(rec)
  }
  function enqueue(rec) { if (!rec || rec.isFolder) return; var idx = root.queueIndexForId(rec.id); if (idx < 0) { root.queue = root.queue.concat([rec]); root.uiTick++ } }
  function clearQueue() { root.queue = []; root.continuation = []; root.queueIndex = -1; root.current = null; root.phase = "stopped"; root.uiTick++ }

  function saveKey(key, val) {
    if (["serverUrl","apiKey","userId","plexToken","clientId"].indexOf(key) === -1) return
    writeConfigProc.collected = ""
    writeConfigProc.command = ["/usr/bin/python3", helperWrite, shellJson, pluginId, key, val || "CLEAR"]
    writeConfigProc.running = true
    console.log("finamp: saving " + key + (val ? "" : " (clear)"))
  }
  function applyServer(srv) {
    if (!srv) return
    var u = String(srv.url || "")
    if (!u) return
    root.serverType = String(srv.type || "jellyfin")
    root.saveKey("serverUrl", u)
    root.statusText = "connected → " + String(srv.name || srv.host || "") + " (" + srv.type + (srv.wizard ? ", wizard pending" : "") + ")"
    if (srv.wizard) { root.wizardPending = true }
    Qt.callLater(function(){ root.mediaOk = false; root.fetchMedia() })
  }
  function discover() {
    root.statusText = "probing tailnet for Jellyfin/Plex…"
    probeProc.collected = ""
    probeProc.command = ["/usr/bin/python3", helperProbe, cacheProbe]
    probeProc.running = true
  }
  function fetchMedia(explicitServer, explicitKey, parentId) {
    var srv = String(explicitServer || root.serverUrl || "")
    var key = String(explicitKey !== undefined ? explicitKey : root.apiKey || "")
    if (!srv) { root.mediaOk = false; return }
    var pid = String(parentId || "")
    root.statusText = pid ? "browsing folder…" : "fetching library from " + srv + "…"
    mediaProc.collected = ""
    mediaProc.command = ["/usr/bin/python3", helperMedia, srv, key, root.userId, pid ? root.cacheBrowse : root.cacheMedia, root.libraryOnly, pid]
    mediaProc.running = true
  }
  function tick() { root.refreshTick++; root.uiTick++ }
  function refresh() { root.tick(); root.fetchMedia() }

  function hydrateCache() {
    var t = cacheMediaFile.text()
    if (!t || root.dataItems.length !== 0) return
    try {
      var c = JSON.parse(t)
      if (c && c.ok) {
        root.dataViews = (c.views || []).map(function(v){ return T.normalizeView(v) })
        root.dataItems = root.reclassifyItems((c.items || []).map(function(it){ return T.normalizeJellyfinItem(it) }))
        root.serverName = String(c.serverName || "")
        root.serverVersion = String(c.serverVersion || "")
        root.userId = String(c.userId || "")
        root.mediaOk = true
        root.tick()
        console.log("finamp: cached " + root.dataItems.length + " items")
      }
    } catch(e) { }
  }

  // Detect MusicAlbum folders that are actually artist containers.
  // Jellyfin sometimes misclassifies artist-level folders as MusicAlbum
  // when the library is flat (no ParentId hierarchy).  Heuristic: if a
  // MusicAlbum folder's name matches the artist prefix of audio tracks
  // named "Artist – Track", reclassify it as MusicArtist.
  function reclassifyItems(items) {
    if (!items || items.length < 2) return items
    var artistNames = {}
    var i
    for (i = 0; i < items.length; i++) {
      var a = items[i]
      if (a && a.type === "Audio" && a.name) {
        var sep = a.name.indexOf(" - ")
        if (sep < 0) sep = a.name.indexOf(" – ")
        if (sep > 0) {
          var artist = a.name.substring(0, sep).trim()
          if (artist) artistNames[artist] = (artistNames[artist] || 0) + 1
        }
      }
    }
    var hasArtists = false
    for (var k in artistNames) { hasArtists = true; break }
    if (!hasArtists) return items
    var out = []
    var reclassified = 0
    for (i = 0; i < items.length; i++) {
      var it = items[i]
      if (it && it.type === "MusicAlbum" && it.isFolder && it.name && artistNames[it.name]) {
        var copy = {}
        for (var key in it) copy[key] = it[key]
        copy.type = "MusicArtist"
        out.push(copy)
        reclassified++
      } else {
        out.push(it)
      }
    }
    if (reclassified) console.log("finamp: reclassified " + reclassified + " folder(s) as MusicArtist")
    return out
  }

  function handleProbe() {
    var txt = probeProc.collected; probeProc.collected = ""
    try {
      var j = JSON.parse(txt)
      root.discovered = j.servers || []
      if (root.discovered.length) root.statusText = root.discovered.length + " media server(s) found on tailnet"
      else root.statusText = "no media servers found — " + String(j.error || "run tailscale up / finish server wizard")
      console.log("finamp: probe " + root.discovered.length + " servers")
    } catch(e) { root.statusText = "probe parse error: " + e }
  }
  function handleMedia() {
    var txt = mediaProc.collected; mediaProc.collected = ""
    try {
      var j = JSON.parse(txt)
      if (j && j.ok) {
        root.mediaOk = true; root.mediaError = ""
        root.dataViews = (j.views || []).map(function(v){ return T.normalizeView(v) })
        root.dataItems = root.reclassifyItems((j.items || []).map(function(it){ return T.normalizeJellyfinItem(it) }))
        root.serverName = String(j.serverName || "")
        root.serverVersion = String(j.serverVersion || "")
        root.serverId = String(j.serverId || "")
        root.wizardPending = !!j.wizard
        root.tick()
        root.statusText = "library: " + root.dataViews.length + " views · " + root.dataItems.length + " items · " + (root.serverName || "Jellyfin") + " " + root.serverVersion
        console.log("finamp: loaded " + root.dataItems.length + " items")
      } else {
        root.mediaOk = false
        var err = String(j && j.error || "unknown").slice(0, 120)
        root.mediaError = err
        if (err.indexOf("auth") !== -1) {
          if (root.apiKey) root.statusText = "API key rejected (401) — regenerate in Jellyfin Dashboard → API Keys"
          else root.statusText = "auth required — add an API key in Settings (Jellyfin Dashboard → API Keys)"
        }
        else if (root.wizardPending || err.indexOf("Not Found") !== -1) root.statusText = "server needs setup — open the Jellyfin wizard"
        else root.statusText = "fetch failed: " + err
        // still surface cached views/items if present
        if (j && (j.views || j.items)) { root.dataViews = (j.views||[]).map(T.normalizeView); root.dataItems = root.reclassifyItems((j.items||[]).map(T.normalizeJellyfinItem)); root.mediaOk = true; root.tick() }
        console.log("finamp: media error " + err)
      }
    } catch(e) { root.statusText = "media parse error: " + e }
  }
  function openInMpv(rec) {
    if (!rec) return
    var isVideo = String(rec.mediaType || "").toLowerCase() === "video"
    var args = ["/usr/bin/mpv", "--title=finamp"]
    if (!isVideo) args.push("--no-video", "--audio-display=no")
    if (root.apiKey) args.push("--http-header-fields=X-Emby-Token:" + root.apiKey)
    args.push(root.streamUrl(rec, false))
    mpvProc.command = args
    mpvProc.running = true
  }
  function download(rec) {
    if (!rec || !rec.id) return
    var ext = root.extFor(rec)
    var safe = String(rec.name || rec.id).replace(/[\\/:*?"<>|]/g, "_").slice(0, 120) || "finamp-download"
    var dir = root.downloadDirPath || (root.homeDir + "/Downloads/finamp")
    var out = dir + "/" + safe + "." + ext
    var u = root.downloadUrl(rec)
    if (!u) { root.statusText = "download: no URL"; return }
    root.statusText = "Downloading → " + safe + "." + ext
    console.log("finamp: downloading " + out)
    root.pendingDownloadId = String(rec.id)
    root.pendingDownloadName = String(rec.name || rec.id)
    root.pendingDownloadPath = out
    dlProc.collected = ""
    dlProc.command = ["/usr/bin/curl", "-sSL", "--fail", "--connect-timeout", "8", "--max-time", "120", "--create-dirs", "-o", out, u]
    dlProc.running = true
  }
  function isDownloaded(rec) {
    if (!rec || !rec.id) return false
    return root.downloads[String(rec.id)] !== undefined
  }
  function downloadedPathFor(rec) {
    if (!rec || !rec.id) return ""
    var e = root.downloads[String(rec.id)]
    return e ? e.path : ""
  }
  function offload(rec) {
    if (!rec || !rec.id) return
    var p = root.downloadedPathFor(rec)
    if (!p) { root.statusText = "offload: not downloaded"; return }
    root.statusText = "Removing → " + p.slice(p.lastIndexOf("/") + 1)
    console.log("finamp: offloading " + p)
    root.pendingRemovedId = String(rec.id)
    offloadProc.collected = ""
    offloadProc.command = ["/bin/rm", "-f", p]
    offloadProc.running = true
  }
  function noteDownloaded(id) {
    downloadsManagerProc.collected = ""
    downloadsManagerProc.command = ["/usr/bin/python3", helperDownloads, "add", downloadsPath, id, root.pendingDownloadName || "", root.pendingDownloadPath || ""]
    downloadsManagerProc.running = true
  }
  function noteRemoved(id) {
    downloadsManagerProc.collected = ""
    downloadsManagerProc.command = ["/usr/bin/python3", helperDownloads, "remove", downloadsPath, id]
    downloadsManagerProc.running = true
  }
  function probeDownloads() {
    downloadsManagerProc.collected = ""
    downloadsManagerProc.command = ["/usr/bin/python3", helperDownloads, "verify", downloadsPath]
    downloadsManagerProc.running = true
  }

  // ---- playlists ----
  property var playlists: []
  property string activePlaylistId: ""
  property var pendingToggleRec: null
  readonly property string playlistsCacheDir: cacheDir + "/playlists"
  readonly property string playlistsCacheFile: root.playlistsCacheDir + "/playlists.json"

  function playlistIndexForId(id) {
    var key = String(id)
    for (var i = 0; i < root.playlists.length; i++) if (String(root.playlists[i].id) === key) return i
    return -1
  }
  function playlistForId(id) {
    var i = root.playlistIndexForId(id)
    return i >= 0 ? root.playlists[i] : null
  }
  function playlistsForItem(rec) {
    if (!rec || !rec.id) return []
    var key = String(rec.id)
    var out = []
    for (var i = 0; i < root.playlists.length; i++) {
      var ids = root.playlists[i].itemIds || []
      for (var j = 0; j < ids.length; j++) if (String(ids[j]) === key) { out.push(root.playlists[i]); break }
    }
    return out
  }
  function playlistItems(pid) {
    var p = root.playlistForId(pid)
    if (!p) return []
    var ids = {}
    for (var i = 0; i < (p.itemIds || []).length; i++) ids[String(p.itemIds[i])] = true
    var out = []
    for (var k = 0; k < root.dataItems.length; k++) {
      var rec = root.dataItems[k]
      if (rec && ids[String(rec.id)] && !rec.isFolder) out.push(rec)
    }
    return out
  }
  function playlistCount(pid) { var p = root.playlistForId(pid); return p ? (p.itemIds || []).length : 0 }

  function hydratePlaylists(j) {
    root.playlists = (j && j.playlists) || []
    for (var i = 0; i < root.playlists.length; i++) {
      var p = root.playlists[i]
      if (typeof p.itemIds !== "object" || !p.itemIds) p.itemIds = []
    }
    console.log("finamp: " + root.playlists.length + " playlists")
  }

  function handlePlaylists() {
    var txt = playlistsManagerProc.collected; playlistsManagerProc.collected = ""
    var last = ""
    var lines = txt.split("\n")
    for (var i = 0; i < lines.length; i++) { var l = String(lines[i]).trim(); if (l) last = l }
    try {
      var j = JSON.parse(last || "{}")
      if (j && j.ok) {
        var hadPending = !!root.pendingToggleRec
        var pendingRec = root.pendingToggleRec
        root.pendingToggleRec = null
        root.hydratePlaylists(j)
        if (!root.activePlaylistId && root.playlists.length) root.activePlaylistId = String(root.playlists[0].id)
        if (hadPending && pendingRec && root.activePlaylistId) {
          root.addToPlaylist(root.activePlaylistId, pendingRec)
          root.statusText = "playlist “" + (root.playlistForId(root.activePlaylistId) && root.playlistForId(root.activePlaylistId).name || "?") + "” + " + String(pendingRec.name || "")
        } else {
          root.statusText = root.playlists.length + " playlist(s) synced ✓"
        }
      } else {
        root.statusText = "playlists: " + String(j && j.error || "error")
      }
    } catch(e) { root.statusText = "playlists parse error: " + e }
  }

  function runPlaylistsManager(args) {
    playlistsManagerProc.collected = ""
    var cmd = ["/usr/bin/python3", helperPlaylists].concat(args)
    playlistsManagerProc.command = cmd
    playlistsManagerProc.running = true
  }
  function createPlaylist(name) {
    if (!name || !String(name).trim().length) return
    var ident = String(Date.now())
    var safe = String(name).replace(/[\x00\n]/g, "").slice(0, 200)
    if (!safe) safe = "New Playlist"
    root.runPlaylistsManager(["add", root.playlistsCacheFile, ident, safe])
  }
  function renamePlaylist(pid, name) {
    if (!pid || !name || !String(name).trim().length) return
    var safe = String(name).replace(/[\x00\n]/g, "").slice(0, 200)
    if (!safe) return
    root.runPlaylistsManager(["rename", root.playlistsCacheFile, String(pid), safe])
  }
  function removePlaylist(pid) {
    if (!pid) return
    if (String(pid) === String(root.activePlaylistId)) root.activePlaylistId = ""
    root.runPlaylistsManager(["remove", root.playlistsCacheFile, String(pid)])
  }
  function addToPlaylist(pid, rec) {
    if (!pid || !rec || !rec.id) return
    var p = root.playlistForId(pid)
    if (!p) return
    var key = String(rec.id)
    for (var i = 0; i < (p.itemIds || []).length; i++) if (String(p.itemIds[i]) === key) return
    root.runPlaylistsManager(["additem", root.playlistsCacheFile, String(pid), key])
  }
  function removeFromPlaylist(pid, rec) {
    if (!pid || !rec || !rec.id) return
    root.runPlaylistsManager(["removeitem", root.playlistsCacheFile, String(pid), String(rec.id)])
  }
  function probePlaylists() {
    var p = root.playlistIndexForId(root.activePlaylistId)
    if (p < 0) root.activePlaylistId = root.playlists.length ? String(root.playlists[0].id) : ""
    root.runPlaylistsManager(["verify", root.playlistsCacheFile])
  }
  function playPlaylist(pid) {
    var items = root.playlistItems(pid)
    if (!items.length) { root.statusText = "playlist is empty"; return }
    root.queue = items.concat([])
    root.queueIndex = 0
    root.current = items[0]
    root.phase = "playing"
    root.activePlaylistId = String(pid)
    root.statusText = "playing “" + (root.playlistForId(pid) && root.playlistForId(pid).name || "?") + "” · " + items.length + " tracks"
    console.log("finamp: play playlist " + String(pid) + " with " + items.length + " tracks")
  }
  function togglePlaylistPill(rec) { root.togglePlaylist(rec) }
  function cycleSpectrum() {
    var modes = ["bars", "wave", "circle", "none"]
    var i = 0
    for (var k = 0; k < modes.length; k++) if (String(root.spectrumMode) === modes[k]) i = (k + 1) % modes.length
    root.spectrumMode = modes[i]
    root.saveKey("spectrumMode", modes[i])
    root.statusText = "visualizer: " + (modes[i] === "none" ? "off" : modes[i])
    console.log("finamp: spectrum mode " + modes[i])
  }
  function spectrumLabel() {
    var m = String(root.spectrumMode || "bars")
    return m === "bars" ? "BARS" : m === "wave" ? "WAVE" : m === "circle" ? "CIRCLE" : "OFF"
  }
  function addToQueue(rec) { root.enqueue(rec) }
  function isInQueue(rec) { if (!rec) return false; var k = String(rec.id); return root.queueIndexForId(k) >= 0 }
  function togglePlaylist(rec) {
    if (!rec) return
    if (rec.isFolder) { root.playItem(rec); return }
    root.pendingToggleRec = null
    if (root.playlists.length === 0) {
      root.activePlaylistId = ""
      root.createPlaylist("My Picks")
      root.pendingToggleRec = rec
      root.statusText = "created “My Picks” — adding “" + String(rec.name || "") + "”…"
      return
    }
    var pid = root.activePlaylistId
    if (!pid || !root.playlistForId(pid)) pid = root.playlists.length ? String(root.playlists[0].id) : ""
    if (!pid) { root.statusText = "create a playlist first"; return }
    var p = root.playlistForId(pid)
    var key = String(rec.id)
    var has = false
    for (var i = 0; i < (p.itemIds || []).length; i++) if (String(p.itemIds[i]) === key) has = true
    if (has) root.removeFromPlaylist(pid, rec)
    else root.addToPlaylist(pid, rec)
    root.statusText = "playlist “" + (p.name || "?") + "” " + (has ? "— removed " : "+ added ") + String(rec.name || "")
  }
  function extFor(rec) {
    var exts = String(rec.raw && rec.raw.Container || "").split(",")
    for (var i = 0; i < exts.length; i++) exts[i] = String(exts[i]).trim().toLowerCase()
    var isAudio = String(rec.mediaType || "").toLowerCase() === "audio"
    var pref = isAudio ? ["m4a","mp3","aac","flac","m4b","wav","ogg"] : ["mp4","mkv","webm","avi","mov","m4v"]
    for (var p = 0; p < pref.length; p++) for (var j = 0; j < exts.length; j++) if (exts[j] === pref[p]) return exts[j]
    if (exts.length && exts[0]) return exts[0]
    return isAudio ? "m4a" : "mp4"
  }
  function openWeb() {
    if (!root.serverUrl) return
    var u = root.serverUrl + "/web/"
    openProc.command = ["/usr/bin/xdg-open", u]
    openProc.running = true
  }

  // ---- processes ----
  Process { id: mkdirProc }
  Process {
    id: probeProc
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ probeProc.collected += data + "\n" } }
    stderr: SplitParser { onRead: function(data){ probeProc.collected += data + "\n" } }
    onExited: function(code, status){ root.handleProbe() }
  }
  Process {
    id: mediaProc
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ mediaProc.collected += data + "\n" } }
    stderr: SplitParser { onRead: function(data){ if (String(data).trim().length) root.statusText = "helper: " + String(data).trim().slice(0, 120) } }
    onExited: function(code, status){ root.handleMedia() }
  }
  Process {
    id: writeConfigProc
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ writeConfigProc.collected += data + "\n" } }
    stderr: SplitParser { onRead: function(data){ writeConfigProc.collected += data + "\n" } }
    onExited: function(code, status){
      if (code !== 0) {
        var why = String(writeConfigProc.collected).split("\n").filter(function(l){ return l.trim().length }).join(" · ")
        root.statusText = "save failed: " + (why ? why.slice(0,120) : "write-config exited " + code)
      } else {
        root.statusText = "saved ✓"
        console.log("finamp: config saved")
      }
    }
  }
  Process { id: mpvProc }
  Process { id: openProc }
  Process {
    id: playlistsManagerProc
    property string collected: ""
    stdout: SplitParser { onRead: function(d){ playlistsManagerProc.collected += d + "\n" } }
    stderr: SplitParser { onRead: function(d){ playlistsManagerProc.collected += d + "\n" } }
    onExited: function(code, status){ root.handlePlaylists() }
  }
  Process {
    id: dlDirProc
    property string collected: ""
    stdout: SplitParser { onRead: function(d){ dlDirProc.collected += d + "\n" } }
    onExited: function(code, status){
      var d = String(dlDirProc.collected).trim()
      root.downloadDirPath = (d && d.startsWith("/")) ? d.replace(/\/+$/, "") + "/finamp" : ""
    }
  }
  Process {
    id: dlProc
    property string collected: ""
    stdout: SplitParser { onRead: function(d){ dlProc.collected += d + "\n" } }
    stderr: SplitParser { onRead: function(d){ dlProc.collected += d + "\n" } }
    onExited: function(code, status){
      if (code === 0) { root.statusText = "Downloaded ✓ → " + (root.downloadDirPath || "Downloads"); console.log("finamp: downloaded ok"); root.noteDownloaded(root.pendingDownloadId) }
      else { root.statusText = "download failed (exit " + code + ")"; console.log("finamp download: " + String(dlProc.collected).slice(0, 200)) }
    }
  }
  Process {
    id: offloadProc
    property string collected: ""
    stdout: SplitParser { onRead: function(d){ offloadProc.collected += d + "\n" } }
    stderr: SplitParser { onRead: function(d){ offloadProc.collected += d + "\n" } }
    onExited: function(code, status){
      if (code === 0) {
        root.statusText = "Removed ✓"
        console.log("finamp: offloaded ok")
        root.noteRemoved(root.pendingRemovedId)
      } else { root.statusText = "removal failed (exit " + code + ")" }
    }
  }
  Process {
    id: downloadsManagerProc
    property string collected: ""
    stdout: SplitParser { onRead: function(d){ downloadsManagerProc.collected += d + "\n" } }
    stderr: SplitParser { onRead: function(d){ downloadsManagerProc.collected += d + "\n" } }
    onExited: function(code, status){
      if (code !== 0) { console.log("finamp downloads-manager: " + String(downloadsManagerProc.collected).slice(0, 200)); return }
      try {
        var j = JSON.parse(String(downloadsManagerProc.collected).split("\n").filter(function(l){ return l.trim().length }).pop())
        var map = {}
        for (var i = 0; i < (j.downloads || []).length; i++) {
          var e = j.downloads[i]
          if (e && e.id && e.path && String(e.exists) === "true") map[String(e.id)] = { path: e.path, name: e.name }
        }
        root.downloads = map
        console.log("finamp: tracked " + Object.keys(map).length + " downloads")
      } catch(e) { root.statusText = "downloads parse error: " + e }
    }
  }
  property var downloads: ({})
  readonly property bool downloading: dlProc.running
  property var pendingDownloadId: ""
  property string pendingDownloadName: ""
  property string pendingDownloadPath: ""
  property string pendingRemovedId: ""
  property string downloadDirPath: ""

  Timer { id: timerMedia; interval: 900000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchMedia() }   // 15m library refresh

  Timer { id: startupTimer; interval: 600; running: true; repeat: false; triggeredOnStart: false; onTriggered: {
    root.hydrateCache()
    root.probeDownloads()
    root.probePlaylists()
    if (root.serverUrl) { root.fetchMedia() }
    else if (root.dataItems.length === 0) { root.discover() }
  } }

  onDataItemsChanged: root.buildOrders()

  Component.onCompleted: {
    console.log("finamp: starting — cacheDir " + cacheDir)
    mkdirProc.command = ["/usr/bin/mkdir", "-p", cacheDir]
    mkdirProc.running = true
    dlDirProc.command = ["/bin/sh", "-c", "d=$(xdg-user-dir DOWNLOAD 2>/dev/null || printf %s \"$HOME/Downloads\"); printf %s \"$d\""]
    dlDirProc.running = true
    if (root.dataItems.length) root.dataItems = root.reclassifyItems(root.dataItems)
  }
}