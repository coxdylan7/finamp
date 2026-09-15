#!/usr/bin/python3
"""Probe the tailnet for Jellyfin/Plex servers.

Runs `tailscale status --json`, enumerates online peers, probes Jellyfin
(8096/8920) and Plex (32400) on each host. Outputs JSON to stdout:
{"servers":[{host,dns,port,type,name,version,id,wizard,url}], "error":""}
argv-only, no media bytes buffered, 2s per probe.
"""
import sys, json, subprocess, urllib.request, urllib.parse, ssl, socket

PORT_JF = 8096
PORT_JF_HTTPS = 8920
PORT_PLEX = 32400
TIMEOUT = 2

def print_result(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")))
    sys.stdout.write("\n")
    sys.stdout.flush()

def http_json(url, timeout=TIMEOUT):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": "finamp/0.1 (tailscale media; https://github.com/coxdylan7/finamp)"})
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        raw = r.read(256 * 1024)
        return json.loads(raw.decode("utf-8", "replace"))

def http_text(url, timeout=TIMEOUT):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": "finamp/0.1 (tailscale media)"})
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.read(64 * 1024).decode("utf-8", "replace")

def probe_jellyfin(host, dns):
    out = []
    for port, scheme in ((PORT_JF, "http"), (PORT_JF_HTTPS, "https")):
        base = f"{scheme}://{host}:{port}"
        try:
            info = http_json(base + "/System/Info/Public")
            if info and info.get("ProductName"):
                out.append({
                    "host": host, "dns": dns, "port": port, "scheme": scheme,
                    "type": "jellyfin", "name": str(info.get("ServerName") or "Jellyfin"),
                    "version": str(info.get("Version") or ""), "id": str(info.get("Id") or ""),
                    "wizard": bool(info.get("StartupWizardCompleted") is False),
                    "url": base
                })
                return out
        except Exception:
            continue
    return out

def probe_plex(host, dns):
    base = f"http://{host}:{PORT_PLEX}"
    try:
        txt = http_text(base + "/identity")
        # /identity returns XML with machineIdentifier=<uuid>
        mid = ""
        if "machineIdentifier=" in txt:
            i = txt.index("machineIdentifier=\"") + len("machineIdentifier=\"")
            j = txt.index("\"", i)
            mid = txt[i:j]
        if mid:
            return [{
                "host": host, "dns": dns, "port": PORT_PLEX, "scheme": "http",
                "type": "plex", "name": "Plex", "version": "", "id": mid,
                "wizard": False, "url": base
            }]
    except Exception:
        pass
    return []

def main():
    servers = []
    error = ""
    try:
        cp = subprocess.run(["/usr/bin/tailscale", "status", "--json"],
                            capture_output=True, text=True, timeout=8)
        if cp.returncode != 0:
            error = "tailscale status failed"
        else:
            status = json.loads(cp.stdout or "{}")
            self_id = (status.get("Self") or {}).get("ID") or ""
            peers = status.get("Peer") or {}
            hosts = []
            for pid, peer in peers.items():
                if pid == self_id:
                    continue
                if not peer.get("Online"):
                    continue
                dns = peer.get("DNSName") or ""
                ips = peer.get("TailscaleIPs") or []
                if not ips:
                    continue
                addr = ips[0]
                hosts.append((addr, dns.rstrip(".") if dns else addr))
            seen = set()
            for addr, dns in hosts:
                if dns and (dns in seen): continue
                if dns: seen.add(dns)
                for s in probe_jellyfin(addr, dns) + probe_plex(addr, dns):
                    servers.append(s)
    except Exception as e:
        error = str(e)[:200]
    print_result({"servers": servers, "error": error})

if __name__ == "__main__":
    main()