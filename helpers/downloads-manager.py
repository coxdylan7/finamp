#!/usr/bin/python3
"""Track Finamp downloads on this machine.

Usage:
  downloads-manager.py add <cacheFile> <id> <name> <path>
  downloads-manager.py remove <cacheFile> <id>
  downloads-manager.py verify <cacheFile>

-add records a downloaded item / -remove deletes a record; both rewrite the
 cache atomically. -verify re-checks on-disk existence of every recorded path
 and rewrites the cache with up-to-date exists flags.

Cache format (JSON array):
  [{"id":str,"name":str,"path":str,"exists":bool}]

Output (stdout, final line): JSON {"ok":bool,"error":str,
  "downloads":[{id,name,path,exists}]} after the operation.
"""
import sys, os, json, pathlib, secrets, stat

MAX_BYTES = 1048576

def fail(msg):
    print(json.dumps({"ok": False, "error": str(msg)[:300], "downloads": []}))
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
    import tempfile
    parent = os.path.dirname(path)
    base = os.path.basename(path)
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".finamp-dl-", dir=parent)
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

def main():
    if len(sys.argv) < 3:
        fail("usage: downloads-manager.py <add|remove|verify> <cacheFile> [args...]")
    mode = sys.argv[1]
    cache = sys.argv[2]
    if any(c in cache for c in ["\x00", "\n"]):
        fail("invalid cache path")
    cache = os.path.abspath(cache)
    cache_dir = os.path.dirname(cache)
    home = os.environ.get("HOME") or os.path.expanduser("~")
    if not (cache_dir == home or cache_dir.startswith(home + os.sep)):
        fail("cache must live under HOME")

    if mode == "add":
        if len(sys.argv) != 6:
            fail("add needs <cacheFile> <id> <name> <path>")
        _, _, ident, name, p = sys.argv[1:6]
        if any(c in ident for c in ["\x00", "\n"]) or len(ident) > 300:
            fail("invalid id")
        downloads = [d for d in read_cache(cache) if d.get("id") != ident]
        downloads.append({"id": ident, "name": name[:300], "path": p, "exists": os.path.isfile(p)})
        try:
            atomic_write(cache, json.dumps(downloads, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "downloads": downloads})
    elif mode == "remove":
        if len(sys.argv) != 4:
            fail("remove needs <cacheFile> <id>")
        ident = sys.argv[3]
        downloads = [d for d in read_cache(cache) if d.get("id") != ident]
        try:
            atomic_write(cache, json.dumps(downloads, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "downloads": downloads})
    elif mode == "verify":
        downloads = read_cache(cache)
        for d in downloads:
            p = d.get("path", "")
            d["exists"] = os.path.isfile(p) if p else False
        try:
            atomic_write(cache, json.dumps(downloads, separators=(",", ":")).encode("utf-8"))
        except Exception as e:
            fail("write: " + str(e))
        out({"ok": True, "error": "", "downloads": downloads})
    else:
        fail("unknown mode: " + mode)

if __name__ == "__main__":
    main()