// Finamp — config helpers + Jellyfin/Plex URL builders + item normalizers.
if (typeof module !== "undefined" && module.exports) module.exports = this

function pluginEntry(shell, pluginId) {
  if (!shell || !shell.shellConfig || !shell.shellConfig.plugins) return null
  var pl = shell.shellConfig.plugins
  for (var i = 0; i < pl.length; i++) {
    if (pl[i] && pl[i].id === pluginId) return pl[i]
  }
  return null
}

function configStr(entry, key, fb) {
  if (entry && entry[key] !== undefined && entry[key] !== null) return String(entry[key])
  return fb !== undefined ? fb : ""
}

function configBool(entry, key, fb) {
  if (entry && entry[key] !== undefined) return entry[key] === true || entry[key] === 1 || String(entry[key]).toLowerCase() === "true"
  return fb !== undefined ? fb : false
}

function configInt(entry, key, fb) {
  if (entry && Number(entry[key])) return Number(entry[key])
  return fb !== undefined ? fb : 0
}

function configFloat(entry, key, fb) {
  if (entry && entry[key] !== undefined && isFinite(Number(entry[key]))) return Number(entry[key])
  return fb !== undefined ? fb : 0
}

function normalizedServer(url) {
  var s = String(url || "").trim()
  while (s.length && s.slice(-1) === "/") s = s.slice(0, -1)
  return s
}

// Approximate advance width of monospace bold text at a pixel size (for auto-sizing WavySprite).
function textAdvance(text, px) {
  var t = String(text || "")
  return t ? Math.ceil(t.length * (Number(px) || 14) * 0.62) : 0
}

function jellyfinImageUrl(server, itemId, tag, apiKey, w) {
  var s = normalizedServer(server)
  if (!s || !itemId || String(itemId).indexOf(":") !== -1) return ""
  var u = s + "/Items/" + encodeURIComponent(String(itemId)) + "/Images/Primary"
  var q = []
  if (w) q.push("maxWidth=" + w)
  if (tag) q.push("tag=" + encodeURIComponent(String(tag)))
  if (apiKey) q.push("ApiKey=" + encodeURIComponent(String(apiKey)))
  return u + "?" + q.join("&")
}

function jellyfinStreamUrl(server, item, apiKey, transcode) {
  var s = normalizedServer(server)
  if (!s || !item) return ""
  var id = item.id || (item.raw && item.raw.Id) || ""
  if (!id) return ""
  var mt = String(item.mediaType || (item.raw && item.raw.MediaType) || "Video")
  var ab = mt.toLowerCase() === "audio"
  var u
  if (transcode) u = s + "/Videos/" + encodeURIComponent(String(id)) + "/stream.mp4"
  else u = s + (ab ? "/Audio/" : "/Videos/") + encodeURIComponent(String(id)) + "/stream"
  var q = []
  q.push("static=" + (transcode ? "false" : "true"))
  var ms = item.mediaSourceId || (item.raw && item.raw.MediaSourceId) || ""
  if (ms) q.push("MediaSourceId=" + encodeURIComponent(String(ms)))
  if (apiKey) q.push("ApiKey=" + encodeURIComponent(String(apiKey)))
  return u + "?" + q.join("&")
}

function jellyfinDownloadUrl(server, itemId, apiKey) {
  var s = normalizedServer(server)
  if (!s || !itemId) return ""
  return s + "/Items/" + encodeURIComponent(String(itemId)) + "/Download?ApiKey=" + encodeURIComponent(String(apiKey || ""))
}

function normalizeJellyfinItem(it) {
  if (!it) return null
  var name = String(it.Name || it.Name || it.Id || "")
  var type = String(it.Type || "Item")
  var mediaType = String(it.MediaType || (type === "Audio" ? "Audio" : (type === "Video" ? "Video" : "")))
  var runtime = 0
  if (it.RunTimeTicks) runtime = Math.round(Number(it.RunTimeTicks) / 10000)
  return {
    id: String(it.Id || ""),
    name: name,
    type: type,
    mediaType: mediaType,
    year: it.ProductionYear ? Number(it.ProductionYear) : 0,
    overview: String(it.Overview || ""),
    runtimeMs: runtime,
    isFolder: !!it.IsFolder,
    imageTag: String(it.ImageTags && it.ImageTags.Primary || ""),
    parentId: String(it.ParentId || ""),
    index: it.IndexNumber ? Number(it.IndexNumber) : 0,
    season: it.ParentIndexNumber ? Number(it.ParentIndexNumber) : 0,
    album: String(it.Album || ""),
    artist: String(it.AlbumArtist || (it.AlbumArtists && it.AlbumArtists[0] ? it.AlbumArtists[0].Name : "") || ""),
    genres: Array.isArray(it.Genres) ? it.Genres.map(function(g) { return String(g) }) : [],
    raw: it
  }
}

function normalizeView(v) {
  if (!v) return null
  return {
    id: String(v.Id || ""),
    name: String(v.Name || ""),
    type: String(v.CollectionType || "unknown"),
    imageTag: String(v.ImageTags && v.ImageTags.Primary || "")
  }
}

function formatMs(ms) {
  if (!isFinite(Number(ms)) || ms <= 0) return "0:00"
  var t = Math.round(Number(ms) / 1000)
  var m = Math.floor(t / 60)
  var s = t % 60
  return m + ":" + (s < 10 ? "0" : "") + s
}

function formatClock(ms) {
  var t = Math.floor((ms || 0) / 1000)
  var m = Math.floor(t / 60)
  var s = t % 60
  return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
}