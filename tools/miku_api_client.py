#!/usr/bin/env python3
"""
Miku Music M500 Remote Control CLI Client
Cryptographically authenticated client using HMAC-SHA256 signatures over HTTPS/HTTP.
"""

import argparse
import hashlib
import hmac
import json
import os
import secrets
import ssl
import time
import urllib.error
import urllib.request

DEFAULT_HOST = os.environ.get("MIKU_HOST", "10.7.7.3")
DEFAULT_PORT = int(os.environ.get("MIKU_PORT", "8765"))
DEFAULT_SECRET = os.environ.get("MIKU_SECRET", "")
USE_HTTPS = os.environ.get("MIKU_HTTPS", "0") == "1"

def get_secret(host, port):
    if DEFAULT_SECRET:
        return DEFAULT_SECRET
    # Try reading from ADB if available
    try:
        import subprocess
        out = subprocess.check_output([
            "adb", "-s", f"{host}:5555", "shell",
            "su", "-c", "cat /data/data/com.miku.player/shared_prefs/miku_api_security_prefs.xml"
        ], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            if 'name="api_secret_key"' in line:
                return line.split(">")[1].split("<")[0]
    except (subprocess.SubprocessError, OSError, IndexError):
        pass
    return "miku_m500_default_secret"

def sign_request(secret, method, path, body_bytes):
    clean_path = path.split("?")[0].rstrip("/")
    timestamp = str(int(time.time() * 1000))
    nonce = secrets.token_hex(16)
    body_hash = hashlib.sha256(body_bytes).hexdigest()
    canonical = f"{method.upper()}\n{clean_path}\n{timestamp}\n{nonce}\n{body_hash}"
    sig = hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()
    
    return {
        "X-Miku-Signature": f"sha256={sig}",
        "X-Miku-Timestamp": timestamp,
        "X-Miku-Nonce": nonce,
        "Authorization": f"Bearer {secret}",
        "Content-Type": "application/json; charset=utf-8"
    }

def request(host, port, method, path, payload=None, secret=None, use_https=USE_HTTPS):
    if not secret:
        secret = get_secret(host, port)
        
    proto = "https" if use_https else "http"
    url = f"{proto}://{host}:{port}{path}"
    
    body_bytes = json.dumps(payload).encode("utf-8") if payload is not None else b""
    headers = sign_request(secret, method, path, body_bytes)
    
    req = urllib.request.Request(url, data=body_bytes if body_bytes else None, headers=headers, method=method.upper())
    
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=5) as res:
            res_body = res.read().decode("utf-8")
            try:
                return json.loads(res_body)
            except (json.JSONDecodeError, UnicodeDecodeError):
                return {"raw": res_body, "status": res.status}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        try:
            return json.loads(err_body)
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {"error": str(e), "body": err_body, "status": e.code}
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return {"error": str(e)}

def main():
    parser = argparse.ArgumentParser(description="Miku Music M500 Remote Control CLI")
    parser.add_argument("--host", default=DEFAULT_HOST, help="M500 IP address (default: 10.7.7.3)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="API Port (default: 8443)")
    parser.add_argument("--secret", default=DEFAULT_SECRET, help="HMAC-SHA256 API Secret Key")
    parser.add_argument("--http", action="store_true", help="Use plain HTTP instead of HTTPS")
    
    sub = parser.add_subparsers(dest="command", required=True)
    
    sub.add_parser("ping", help="Ping Miku API server")
    sub.add_parser("status", help="Get full playback and hardware telemetry")
    sub.add_parser("play", help="Resume playback")
    sub.add_parser("pause", help="Pause playback")
    sub.add_parser("toggle", help="Toggle play/pause")
    sub.add_parser("next", help="Next track")
    sub.add_parser("prev", help="Previous track")
    
    seek_p = sub.add_parser("seek", help="Seek to position in ms")
    seek_p.add_argument("ms", type=int, help="Position in milliseconds")
    
    vol_p = sub.add_parser("volume", help="Set volume (0-100) or delta (+/-)")
    vol_p.add_argument("val", type=int, help="Target volume percentage (0-100)")
    
    sub.add_parser("queue", help="List current playback queue")
    
    search_p = sub.add_parser("search", help="Search music library")
    search_p.add_argument("query", help="Search query")
    search_p.add_argument("--limit", type=int, default=20, help="Result limit")
    
    pulsar_p = sub.add_parser("pulsar", help="Configure Pulsar LED")
    pulsar_p.add_argument("--mode", help="Pulsar mode (audiophile_auto, chroma_rainbow, signature_teal, custom)")
    pulsar_p.add_argument("--hex", help="Custom hex color (e.g. #00E5FF)")
    pulsar_p.add_argument("--brightness", type=int, help="Brightness (0-255)")
    
    args = parser.parse_args()
    use_https = not args.http
    
    cmd = args.command
    if cmd == "ping":
        res = request(args.host, args.port, "GET", "/api/v1/ping", secret=args.secret, use_https=use_https)
    elif cmd == "status":
        res = request(args.host, args.port, "GET", "/api/v1/status", secret=args.secret, use_https=use_https)
    elif cmd in ["play", "pause", "toggle", "next", "prev"]:
        endpoint = "previous" if cmd == "prev" else cmd
        res = request(args.host, args.port, "POST", f"/api/v1/playback/{endpoint}", secret=args.secret, use_https=use_https)
    elif cmd == "seek":
        res = request(args.host, args.port, "POST", "/api/v1/playback/seek", {"position_ms": args.ms}, secret=args.secret, use_https=use_https)
    elif cmd == "volume":
        res = request(args.host, args.port, "POST", "/api/v1/playback/volume", {"volume": args.val}, secret=args.secret, use_https=use_https)
    elif cmd == "queue":
        res = request(args.host, args.port, "GET", "/api/v1/queue", secret=args.secret, use_https=use_https)
    elif cmd == "search":
        res = request(args.host, args.port, "GET", f"/api/v1/library/search?q={args.query}&limit={args.limit}", secret=args.secret, use_https=use_https)
    elif cmd == "pulsar":
        payload = {}
        if args.mode: payload["mode"] = args.mode
        if args.hex: payload["hex"] = args.hex
        if args.brightness is not None: payload["brightness"] = args.brightness
        res = request(args.host, args.port, "POST", "/api/v1/hardware/pulsar", payload, secret=args.secret, use_https=use_https)
    else:
        res = {"error": f"Unknown command {cmd}"}
        
    print(json.dumps(res, indent=2))

if __name__ == "__main__":
    main()
