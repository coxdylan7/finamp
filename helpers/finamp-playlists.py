#!/usr/bin/python3
"""Track Finamp playlists on this machine.

Usage:
  finamp-playlists.py add <cacheFile> <id> <name>
  finamp-playlists.py rename <cacheFile> <id> <name>
  finamp-playlists.py remove <cacheFile> <id>
  finamp-playlists.py additem <cacheFile> <pid> <recId>
  finamp-playlists.py removeitem <cacheFile> <pid> <recId>
  finamp-playlists.py verify <cacheFile>

-add creates a playlist record; -rename renames it; -remove deletes
 it. -additem appends a library record id to a playlist (deduping);
 -removeitem drops one. Each rewrites the cache atomically and emits
 the full playlist list so Service can re-hydrate in one shot.
 -verify re-checks cache integrity and rewrites it if needed.

Cache format (JSON array):
  [{"id":str,"name":str,"itemIds":[str,...]}]

Output (stdout, final line): JSON {"ok":bool,"error":str,
  "playlists":[{id,name,itemIds}]}
"""
import sys, os, json, tempfile

MAX_BYTES = 1048576

def fail(msg):
    print(json.dumps({"ok": False, "error": str(msg)[:300], "playlists": []}, separators=(",", ":")))
    sys.exit(1)

def out(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")))
    sys.stdout.write("\n")
    sys.stdout.flush()

def read_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = f.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                return []
            j = json.loads(data)
        return j if isinstance(j, list) else []
    except Exception:
        return []

def atomic_write(path, data_bytes):
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".finamp-pl-", dir=parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data_bytes)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o600)
        os.rename(tmp, path)
    finally:
        if os.path.exists(tmp):
            try: os.unlink(tmp)
            except Exception: pass

def dedupe(ids):
    seen = {}
    out_ = []
    for i in (ids or []):
        s = str(i)
        if s and s not in seen:
            seen[s] = True
            out_.append(s)
    return out_

def main():
    if len(sys.argv) < 3:
        fail("usage: finamp-playlists.py <add|rename|remove|additem|removeitem|verify> <cacheFile> ...")
    mode = sys.argv[1]
    cache = sys.argv[2]
    if any(c in cache for c in ["\x00", "\n"]):
        fail("invalid cache path")
    cache = os.path.abspath(cache)
    cache_dir = os.path.dirname(cache)
    home = os.environ.get("HOME") or os.path.expanduser("~")
    if not (cache_dir == home or cache_dir.startswith(home + os.sep)):
        fail("cache must live under HOME")
    playlists = read_cache(cache)

    if mode == "add":
        if len(sys.argv) != 5:
            fail("add needs <cacheFile> <id> <name>")
        ident, name = sys.argv[3], sys.argv[4]
        if any(c in ident for c in ["\x00", "\n"]) or len(ident) > 300:
            fail("invalid id")
        name = str(name).strip()[:300]
        if not name or any(c in name for c in ["\x00", "\n"]):
            fail("invalid name")
        for p in playlists:
            if str(p.get("id")) == ident:
                fail("playlist id already exists")
        playlists.append({"id": ident, "name": name, "itemIds": []})
        try:
            atomic_write(cache, json.dumps(playlists, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "playlists": playlists})
    elif mode == "rename":
        if len(sys.argv) != 5:
            fail("rename needs <cacheFile> <id> <name>")
        ident, name = sys.argv[3], sys.argv[4]
        name = str(name).strip()[:300]
        if not name or any(c in name for c in ["\x00", "\n"]):
            fail("invalid name")
        found = None
        for p in playlists:
            if str(p.get("id")) == ident:
                found = p; break
        if not found:
            fail("playlist not found")
        found["name"] = name
        try:
            atomic_write(cache, json.dumps(playlists, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "playlists": playlists})
    elif mode == "remove":
        if len(sys.argv) != 4:
            fail("remove needs <cacheFile> <id>")
        ident = sys.argv[3]
        playlists = [p for p in playlists if str(p.get("id")) != ident]
        try:
            atomic_write(cache, json.dumps(playlists, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "playlists": playlists})
    elif mode == "additem":
        if len(sys.argv) != 5:
            fail("additem needs <cacheFile> <pid> <recId>")
        pid, rid = sys.argv[3], sys.argv[4]
        found = None
        for p in playlists:
            if str(p.get("id")) == pid:
                found = p; break
        if not found:
            fail("playlist not found")
        found["itemIds"] = dedupe((found.get("itemIds") or []) + [rid])
        try:
            atomic_write(cache, json.dumps(playlists, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "playlists": playlists})
    elif mode == "removeitem":
        if len(sys.argv) != 5:
            fail("removeitem needs <cacheFile> <pid> <recId>")
        pid, rid = sys.argv[3], sys.argv[4]
        found = None
        for p in playlists:
            if str(p.get("id")) == pid:
                found = p; break
        if not found:
            fail("playlist not found")
        found["itemIds"] = [i for i in (found.get("itemIds") or []) if str(i) != rid]
        try:
            atomic_write(cache, json.dumps(playlists, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "playlists": playlists})
    elif mode == "verify":
        try:
            atomic_write(cache, json.dumps(playlists, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "playlists": playlists})
    else:
        fail("unknown mode: " + mode)

if __name__ == "__main__":
    main()
