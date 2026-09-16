#!/usr/bin/python3
"""Fetch Jellyfin library (views + items) and cache atomically.

Usage: fetch-media.py <serverUrl> <apiKey> <userIdOrEmpty> <cachePath>
argv-only, descriptor-relative, capped reads, atomic nofollow writes.
Output: {"ok":bool,"error":str,"type":"jellyfin","serverName":str,"serverVersion":str,
         "serverId":str,"wizard":bool,"userId":str,"views":[...],"items":[...]}
"""
import sys, os, json, pathlib, stat, secrets, socket, urllib.request, urllib.parse, ssl

MAX_BYTES = 5242880
ITEM_LIMIT = 150
PAGE_LIMIT = 5000
TIMEOUT = 10
UA = "finamp/0.1 (tailscale media; https://github.com/coxdylan7/finamp)"

def fail(msg):
    print(f"fetch-media: {msg}", file=sys.stderr)
    sys.exit(1)

def out_json(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")))
    sys.stdout.write("\n")
    sys.stdout.flush()

# ---------- secure cache path / write helpers ----------

def open_trusted_base(home_path):
    fd = os.open(home_path, os.O_DIRECTORY | os.O_NOFOLLOW)
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
        os.close(fd); fail(f"HOME invalid: {home_path}")
    if st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        os.close(fd); fail("HOME not owned / writable by group")
    return fd

def ensure_parent_descriptor_relative(home_fd, home_path, parent_path):
    if not parent_path.startswith(home_path + os.sep):
        fail(f"parent not under HOME: {parent_path}")
    rel = os.path.relpath(parent_path, home_path)
    cur_fd = os.dup(home_fd)
    for comp in rel.split(os.sep):
        if not comp or comp == ".":
            continue
        if comp == ".." or "/" in comp or "\n" in comp or "\0" in comp:
            try: os.close(cur_fd)
            except: pass
            fail(f"invalid component: {comp}")
        try:
            next_fd = os.open(comp, os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=cur_fd)
            st = os.fstat(next_fd)
            if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
                os.close(next_fd); os.close(cur_fd); fail(f"component invalid: {comp}")
            if st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                os.close(next_fd); os.close(cur_fd); fail(f"component not owned: {comp}")
            try: os.close(cur_fd)
            except: pass
            cur_fd = next_fd
        except OSError as e:
            fail(f"open component {comp}: {e}")
    return cur_fd

def validate_cache_path(p):
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    exp = os.path.join(home, ".cache", "omarchy", "finamp") + os.sep
    if not p.startswith(exp):
        fail(f"cache must be under {exp}")
    if ".." in pathlib.Path(p).parts or "\n" in p or "\r" in p or "\x00" in p:
        fail("invalid cache path")

def atomic_write(path, data_bytes):
    parent = os.path.dirname(path); base = os.path.basename(path)
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    home_fd = open_trusted_base(home)
    try:
        dir_fd = ensure_parent_descriptor_relative(home_fd, home, parent)
    except Exception as e:
        os.close(home_fd); fail(f"ensure parent: {e}")
    try:
        try: os.fchmod(dir_fd, 0o700)
        except Exception: pass
        tmp = f".finamp-tmp-{secrets.token_hex(8)}"
        fd = os.open(tmp, os.O_CREAT | os.O_EXCL | os.O_RDWR | os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        try:
            n = os.write(fd, data_bytes)
            if n != len(data_bytes): fail("short write")
            os.fsync(fd); os.close(fd); fd = -1
            os.rename(tmp, base, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
            tmp = None
            os.chmod(base, 0o600, dir_fd=dir_fd)
        finally:
            if fd >= 0:
                try: os.close(fd)
                except: pass
            if tmp is not None:
                try: os.unlink(tmp, dir_fd=dir_fd)
                except: pass
    finally:
        try: os.close(dir_fd)
        except: pass
        try: os.close(home_fd)
        except: pass

def read_cached(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = f.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                return None
            return json.loads(data)
    except Exception:
        return None

# ---------- arg validation ----------

def valid_host(url):
    u = urllib.parse.urlparse(url)
    if u.scheme not in ("http", "https"):
        return False
    if u.username or u.password:
        return False
    h = (u.hostname or "").lower()
    if h == "localhost":
        return True
    try:
        socket.inet_aton(h)
        return True
    except Exception:
        pass
    return h.endswith(".ts.net")

def main():
    if len(sys.argv) not in (5, 6, 7):
        fail("usage: fetch-media.py <serverUrl> <apiKey> <userIdOrEmpty> <cachePath> [<libraryFilter>] [<parentId>]")
    server = sys.argv[1].strip()
    api_key = sys.argv[2]
    user_id = sys.argv[3].strip()
    cache = sys.argv[4]
    library_filter = (sys.argv[5] if len(sys.argv) > 5 else "music").strip().lower()
    parent_id = (sys.argv[6] if len(sys.argv) > 6 else "").strip()
    if library_filter not in ("all", "movies", "music"):
        fail("libraryFilter must be all|movies|music")
    if len(parent_id) > 128 or any(c in parent_id for c in ["\n", "\r", "\x00"]):
        fail("parentId invalid")

    validate_cache_path(cache)

    if any(c in server for c in ["\n", "\r", "\x00", "'", "`"]):
        fail("serverUrl contains forbidden chars")
    if len(server) > 2048:
        fail("serverUrl too long")
    if not (server.startswith("http://") or server.startswith("https://")):
        fail("serverUrl must be http(s)://")
    if not valid_host(server):
        fail("serverUrl host not allowed (tailscale ts.net / IP / localhost only)")

    api_key = api_key.strip()
    if len(api_key) > 256 or any(c in api_key for c in ["\n", "\r", "\x00", "'", "`"]):
        fail("apiKey invalid")
    if len(user_id) > 128 or any(c in user_id for c in ["\n", "\r", "\x00"]):
        fail("userId invalid")

    while server.endswith("/"):
        server = server[:-1]

    ctx = ssl.create_default_context()

    def get_json(path, params=None):
        q = dict(params or {})
        q["ApiKey"] = api_key
        url = server + path + "?" + urllib.parse.urlencode(q)
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
            raw = r.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                fail("response exceeds byte cap")
            return json.loads(raw.decode("utf-8", "replace"))

    info = {}
    wizard = False
    try:
        info = get_json("/System/Info/Public")
    except Exception:
        pass

    result = {
        "ok": False, "error": "", "type": "jellyfin",
        "serverName": str(info.get("ServerName") or ""),
        "serverVersion": str(info.get("Version") or ""),
        "serverId": str(info.get("Id") or ""),
        "wizard": bool(info.get("StartupWizardCompleted") is False),
        "userId": user_id, "views": [], "items": []
    }
    cached = read_cached(cache)

    # Resolve first user if no userId given
    if not user_id:
        try:
            users = get_json("/Users")
            if isinstance(users, list) and users:
                result["userId"] = str(users[0].get("Id") or "")
        except Exception as e:
            result["error"] = "auth:" + str(e)[:120]
            out_json(result)
            return

    uid = result["userId"]
    try:
        if widget := info.get("StartupWizardCompleted"):
            # wizard incomplete — nothing to browse
            pass
        if not info.get("ProductName"):
            result["error"] = "not a Jellyfin server"
            out_json(result)
            return
        if not uid:
            result["error"] = "no userId (server has no users)"
            out_json(result)
            return

        item_types = {
            "all": "Movie,Series,Season,Episode,MusicAlbum,Audio,MusicArtist,Video",
            "music": "Audio,MusicAlbum,MusicArtist",
            "movies": "Movie",
        }[library_filter]

        if parent_id:
            result["views"] = cached.get("views", []) if isinstance(cached, dict) else []
            items = []
            try:
                parent_item = get_json(f"/Users/{uid}/Items/{parent_id}")
                if isinstance(parent_item, dict) and parent_item.get("Id"):
                    items.append(parent_item)
            except Exception:
                pass
            start = 0
            while start < PAGE_LIMIT:
                page = get_json(f"/Users/{uid}/Items", {
                    "ParentId": parent_id, "Recursive": "true",
                    "IncludeItemTypes": item_types,
                    "Fields": "Overview,ProductionYear,RuntimeTicks,PrimaryImageAspectRatio",
                    "SortBy": "SortName", "SortOrder": "Ascending",
                    "StartIndex": str(start), "Limit": str(ITEM_LIMIT)
                })
                batch = page.get("Items") or []
                for it in batch:
                    if isinstance(it, dict) and it.get("Id"):
                        items.append(it)
                total = int(page.get("TotalRecordCount") or (start + len(batch)))
                start += len(batch)
                if len(batch) < ITEM_LIMIT or start >= total:
                    break
            result["items"] = items
            result["ok"] = True
        else:
            views = get_json(f"/Users/{uid}/Views")
            vout = []
            for v in (views.get("Items") if isinstance(views, dict) else views) or []:
                if isinstance(v, dict) and v.get("Id"):
                    vout.append(v)
            result["views"] = vout

            view_parent = ""
            if library_filter != "all":
                want = {"music": "music", "movies": "movies"}[library_filter]
                for v_ in vout:
                    if str(v_.get("CollectionType") or "") == want:
                        view_parent = str(v_.get("Id") or "")
                        break

            items = []
            start = 0
            while start < PAGE_LIMIT:
                page = get_json(f"/Users/{uid}/Items", {
                    "ParentId": view_parent, "Recursive": "true",
                    "IncludeItemTypes": item_types,
                    "Fields": "Overview,ProductionYear,RuntimeTicks,PrimaryImageAspectRatio",
                    "SortBy": "SortName", "SortOrder": "Ascending",
                    "StartIndex": str(start), "Limit": str(ITEM_LIMIT)
                })
                batch = page.get("Items") or []
                for it in batch:
                    if isinstance(it, dict) and it.get("Id"):
                        items.append(it)
                total = int(page.get("TotalRecordCount") or (start + len(batch)))
                start += len(batch)
                if len(batch) < ITEM_LIMIT or start >= total:
                    break
            result["items"] = items
            result["ok"] = True
    except urllib.error.HTTPError as e:
        result["error"] = "http:" + str(e.code)
        if e.code == 401:
            result["error"] = "auth"
        if cached:
            result["ok"] = cached.get("ok", False)
            result["views"] = cached.get("views", [])
            result["items"] = cached.get("items", [])
            result["userId"] = cached.get("userId", "")
    except Exception as e:
        result["error"] = str(e)[:200]
        if cached:
            result["ok"] = cached.get("ok", False)
            result["views"] = cached.get("views", [])
            result["items"] = cached.get("items", [])
            result["userId"] = cached.get("userId", "")

    try:
        atomic_write(cache, json.dumps(result, separators=(",", ":")).encode("utf-8"))
    except Exception as e:
        result["error"] = str(e)[:120]
    out_json(result)

if __name__ == "__main__":
    main()