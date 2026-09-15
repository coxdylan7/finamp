#!/usr/bin/python3
"""Secure write-config for a plugin entry in shell.json.

Usage: write-config.py <shellJsonPath> <pluginId> [<key> <valueOrCLEAR>]...
argv-only, descriptor-relative, capped reads, atomic nofollow writes.
Supported keys: serverUrl, apiKey, userId, plexToken, clientId, eqPreset.
"""
import sys, os, json, pathlib, stat, secrets, socket, urllib.parse

MAX_BYTES = 5242880
ALLOWED_KEYS = {"serverUrl", "apiKey", "userId", "plexToken", "clientId", "eqPreset", "libraryOnly"}

def fail(msg):
    print(f"write-config: {msg}", file=sys.stderr)
    sys.exit(1)

def open_trusted_base(home_path):
    try:
        fd = os.open(home_path, os.O_DIRECTORY | os.O_NOFOLLOW)
    except Exception as e:
        fail(f"open HOME failed: {e}")
    try:
        st = os.fstat(fd)
    except Exception as e:
        try: os.close(fd)
        except: pass
        fail(f"fstat HOME failed: {e}")
    if not stat.S_ISDIR(st.st_mode):
        try: os.close(fd)
        except: pass
        fail(f"HOME not directory: {home_path}")
    if stat.S_ISLNK(st.st_mode):
        try: os.close(fd)
        except: pass
        fail(f"HOME is symlink: {home_path}")
    if st.st_uid != os.getuid():
        try: os.close(fd)
        except: pass
        fail(f"HOME not owned: {home_path}")
    if st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        try: os.close(fd)
        except: pass
        fail(f"HOME writable by group/other: {home_path} mode {oct(st.st_mode)}")
    return fd

def ensure_parent_descriptor_relative(home_fd, home_path, parent_path):
    if not parent_path.startswith(home_path + os.sep):
        fail(f"parent not under HOME: {parent_path}")
    rel = os.path.relpath(parent_path, home_path)
    parts = rel.split(os.sep)
    cur_fd = os.dup(home_fd)
    cur_path = home_path
    for comp in parts:
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
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component invalid: {os.path.join(cur_path, comp)}")
            if st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component not owned/writable: {os.path.join(cur_path, comp)}")
            try: os.close(cur_fd)
            except: pass
            cur_fd = next_fd
            cur_path = os.path.join(cur_path, comp)
        except OSError as e:
            try: os.close(cur_fd)
            except: pass
            fail(f"open component failed {os.path.join(cur_path, comp)}: {e}")
    return cur_fd

def validate_shell_path(p):
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    exp = os.path.join(home, ".config", "omarchy") + os.sep
    if not p.startswith(exp):
        fail(f"shell.json must be under {exp}")
    if ".." in pathlib.Path(p).parts or "\n" in p or "\r" in p or "\x00" in p:
        fail("invalid shell path")
    return p

def read_json_descriptor_relative(home_fd, home_path, parent_dir, base):
    dir_fd = ensure_parent_descriptor_relative(home_fd, home_path, parent_dir)
    try:
        try:
            fd = os.open(base, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
        except FileNotFoundError:
            return None
        try:
            data = os.read(fd, MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                fail("shell.json exceeds cap")
            return json.loads(data.decode('utf-8'))
        finally:
            os.close(fd)
    finally:
        try: os.close(dir_fd)
        except: pass

def atomic_write(path, data_bytes):
    parent = os.path.dirname(path); base = os.path.basename(path)
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    home_fd = open_trusted_base(home)
    try:
        dir_fd = ensure_parent_descriptor_relative(home_fd, home, parent)
        try:
            os.fchmod(dir_fd, 0o700)
        except Exception as e:
            fail(f"fchmod parent failed: {e}")
    except Exception as e:
        try: os.close(home_fd)
        except: pass
        fail(f"ensure parent failed: {e}")
    try:
        try:
            st = os.fstat(dir_fd)
            if st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                fail("parent not owned/writable")
        except Exception as e:
            fail(f"fstat parent failed: {e}")
        tmp = f".finamp-tmp-{secrets.token_hex(8)}"
        try: fd = os.open(tmp, os.O_CREAT|os.O_EXCL|os.O_RDWR|os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        except Exception as e: fail(f"create tmp failed: {e}")
        try:
            n = os.write(fd, data_bytes)
            if n != len(data_bytes): fail("short write")
            os.fsync(fd); os.close(fd); fd = -1
            try: os.rename(tmp, base, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
            except Exception as e: fail(f"rename failed: {e}")
            tmp = None
            try: os.chmod(base, 0o600, dir_fd=dir_fd)
            except Exception as e: fail(f"chmod final failed: {e}")
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

def allowed_host(url):
    try:
        u = urllib.parse.urlparse(url)
        h = (u.hostname or "").lower()
    except Exception:
        return False
    if h == "localhost":
        return True
    try:
        socket.inet_aton(h)
        return True
    except Exception:
        pass
    return h.endswith(".ts.net")

def validate_value(key, val):
    if key == "CLEAR":
        return val  # handled as remove sentinel, not a real value
    s = str(val)
    if len(s) > 2048:
        fail(f"{key} too long")
    if any(c in s for c in ["\n", "\r", "\x00", "'", "`"]):
        fail(f"{key} contains forbidden chars")
    if key == "serverUrl":
        u = s.lower()
        if not (u.startswith("http://") or u.startswith("https://")):
            fail("serverUrl must be http(s)://")
        if not allowed_host(s):
            fail("serverUrl host not allowed (tailscale ts.net / IP / localhost only)")
    return s

def main():
    if len(sys.argv) < 5 or (len(sys.argv) - 3) % 2 != 0:
        fail(f"usage: {sys.argv[0]} <shellJsonPath> <pluginId> [<key> <valueOrCLEAR>]...")
    shell = sys.argv[1]
    plugin = sys.argv[2]
    validate_shell_path(shell)
    if not plugin or len(plugin) > 64 or any(c in plugin for c in ["\n", "\r", "\0", "/", "\\"]):
        fail("invalid plugin id")

    pairs = []
    for i in range(3, len(sys.argv), 2):
        key = sys.argv[i]
        val = sys.argv[i + 1]
        if key not in ALLOWED_KEYS:
            fail(f"unsupported key: {key}")
        pairs.append((key, val))

    home = os.environ.get("HOME") or str(pathlib.Path.home())
    home_fd = open_trusted_base(home)
    try:
        cfg = read_json_descriptor_relative(home_fd, home, os.path.dirname(shell), os.path.basename(shell))
    finally:
        try: os.close(home_fd)
        except: pass

    if cfg is None:
        cfg = {"version": 1, "plugins": []}
    if not isinstance(cfg, dict):
        fail("shell.json root not object")
    if cfg.get("plugins") is None:
        cfg["plugins"] = []
    plugins = cfg["plugins"]
    if not isinstance(plugins, list):
        fail("plugins not list")
    entry = None
    for p_ in plugins:
        if isinstance(p_, dict) and str(p_.get("id") or "") == plugin:
            entry = p_
            break
    if entry is None:
        entry = {"id": plugin}
        plugins.append(entry)

    applied = {}
    for key, val in pairs:
        if val == "CLEAR":
            entry.pop(key, None)
            applied[key] = "CLEAR"
        else:
            entry[key] = validate_value(key, val)
            applied[key] = entry[key]
    try:
        out = json.dumps(cfg, indent=2).encode('utf-8')
    except Exception as e:
        fail(f"serialize failed: {e}")
    if len(out) > MAX_BYTES:
        fail("shell.json exceeds cap")
    atomic_write(shell, out)
    print(json.dumps({"plugin": plugin, "applied": applied}))

if __name__ == "__main__":
    main()