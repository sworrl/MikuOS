#!/usr/bin/env python3
"""Serve the MikuOS web installer, and give an operator a signed channel into it.

WHY THIS EXISTS
---------------
WebUSB only exists inside a browser tab, so nothing outside the browser can talk to a device
in fastboot mode through this installer. That is normally fine: a human clicks the buttons.
It is not fine when the person maintaining the installer needs to drive a real flash from a
terminal while watching the public UI behave exactly as a stranger would see it.

So this adds a control channel, not a second code path. Commands arrive here, the page picks
them up and performs them through the *same* functions the buttons call, and everything the
page logs comes back. The UI the operator drives is the UI the public gets; there is no
"maintainer mode" that flashes differently.

SECURITY
--------
This channel can brick a device, so it is authenticated end to end and inert by default.

  * Every request in both directions carries an HMAC-SHA256 over a canonical string that
    includes the method, the path, a timestamp, a nonce and the SHA-256 of the body. Replays
    are rejected on the nonce; anything older than CLOCK_SKEW_S is rejected on the timestamp.

  * A command is signed *by the issuer* over the exact bytes it will be delivered as, and the
    browser verifies that inner signature itself before acting. The server never re-serializes
    a command. A compromised control server therefore cannot make the page flash anything:
    it can only withhold or reorder commands, and reordering fails the monotonic seq check.

  * The shared secret is generated locally, stored 0600, and reaches the browser in the URL
    *fragment*, which browsers do not send to servers and do not put in a Referer header.

  * The page runs in public-installer mode with no control code active unless that fragment
    is present. Nothing about the hosted site at mikuos.falcontechnix.com changes.

  * Data-destroying commands (clean install, rollback to stock) must carry a matching
    `confirm` string in the signed envelope, and bootloader unlock is not remotely
    issuable at all - it wipes the device and needs a hand on it.

USAGE
-----
    python3 tools/web-installer/control_server.py --images /path/to/mikuos/out
    # prints the URL to open, fragment included

Then from another terminal: ./mikuctl status, ./mikuctl connect, ./mikuctl start, ...
"""
import argparse
import base64
import hashlib
import hmac
import importlib.util
import json
import os
import secrets
import stat
import sys
import threading
import time
from collections import deque
from http.server import ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))

# Reuse the dev server's Range-capable handler rather than reimplementing it: the installer
# streams the 5 GB super in 63 MiB ranges and a server without Range support silently
# refetches the whole image per chunk.
_spec = importlib.util.spec_from_file_location("miku_serve", os.path.join(HERE, "serve.py"))
_serve = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_serve)

PROTO = "MIKUOSCTL1"          # request-level signing domain
CMD_PROTO = "MIKUOSCMD1"      # command-envelope signing domain
CLOCK_SKEW_S = 300
NONCE_MEMORY = 4096
EVENT_MEMORY = 4000
POLL_WAIT_S = 25.0

SECRET_PATH = os.path.join(HERE, ".control-secret")

# Commands the browser agent understands. Kept here as well as in control.js so the server
# can reject a typo before it reaches a device rather than after.
COMMANDS = {
    "ping": "liveness check; the page answers with its agent version",
    "status": "push a full state snapshot back",
    "load_manifest": "args: url - load a release manifest",
    "connect": "attach to the fastboot device (silent if the browser already has permission)",
    "refresh_info": "re-read getvar and re-evaluate the guard rails",
    "set_override": "args: dev, battery (booleans) - the two guard-rail override checkboxes",
    "select_action": "args: action, with_root - choose an install action and build the plan",
    "goto_step": "args: step (1-5) - move the wizard",
    "start": "run the current plan",
    "abort": "stop after the current chunk",
    "resume": "reconnect if needed and continue from the recorded step/chunk",
    "reboot_bootloader": "send reboot-bootloader",
}
# These lose user data, so the signed envelope must also carry the matching confirm string.
DESTRUCTIVE_ACTIONS = {"install_clean": "WIPE", "rollback_stock": "WIPE"}


def canonical(method: str, path: str, ts: str, nonce: str, body: bytes) -> bytes:
    return "\n".join([PROTO, method.upper(), path, ts, nonce,
                      hashlib.sha256(body).hexdigest()]).encode()


def sign_request(secret: bytes, method: str, path: str, body: bytes):
    ts = str(int(time.time()))
    nonce = secrets.token_hex(12)
    sig = hmac.new(secret, canonical(method, path, ts, nonce, body), hashlib.sha256).hexdigest()
    return {"X-Miku-Ts": ts, "X-Miku-Nonce": nonce, "X-Miku-Sig": sig}


def sign_command(secret: bytes, seq: int, cmd: str, args: dict, confirm: str = "") -> dict:
    """Produce the envelope the browser will verify. The signature covers the exact bytes."""
    env = {"v": 1, "seq": seq, "issued": int(time.time() * 1000),
           "nonce": secrets.token_hex(12), "cmd": cmd, "args": args or {}}
    if confirm:
        env["confirm"] = confirm
    payload = json.dumps(env, sort_keys=True, separators=(",", ":")).encode()
    sig = hmac.new(secret, CMD_PROTO.encode() + b"\n" + payload, hashlib.sha256).hexdigest()
    return {"seq": seq, "payload_b64": base64.b64encode(payload).decode(), "sig": sig}


class Hub:
    """The shared state between the operator and the page. One flash at a time, by design."""

    def __init__(self, secret: bytes):
        self.secret = secret
        self.lock = threading.Condition()
        self.commands = []            # signed envelopes, seq-ordered
        self.events = deque(maxlen=EVENT_MEMORY)
        self.snapshot = {}
        self.results = {}             # seq -> what the page reported back
        self.nonces = deque(maxlen=NONCE_MEMORY)
        self.nonce_set = set()
        self.agent_seen_at = 0.0
        self.agent_version = None

    def check_nonce(self, nonce: str) -> bool:
        with self.lock:
            if nonce in self.nonce_set:
                return False
            if len(self.nonces) == self.nonces.maxlen:
                self.nonce_set.discard(self.nonces[0])
            self.nonces.append(nonce)
            self.nonce_set.add(nonce)
            return True

    def next_seq(self) -> int:
        with self.lock:
            return (self.commands[-1]["seq"] + 1) if self.commands else 1

    def enqueue(self, envelope: dict) -> int:
        with self.lock:
            if self.commands and envelope["seq"] <= self.commands[-1]["seq"]:
                raise ValueError(f"seq {envelope['seq']} is not newer than "
                                 f"{self.commands[-1]['seq']}")
            self.commands.append(envelope)
            self.lock.notify_all()
            return envelope["seq"]

    def since(self, after: int):
        return [c for c in self.commands if c["seq"] > after]

    def wait_for(self, after: int, timeout: float):
        deadline = time.time() + timeout
        with self.lock:
            while True:
                pending = self.since(after)
                if pending:
                    return pending
                left = deadline - time.time()
                if left <= 0:
                    return []
                self.lock.wait(left)

    def ingest(self, body: dict):
        with self.lock:
            self.agent_seen_at = time.time()
            if body.get("agent"):
                self.agent_version = body["agent"]
            for ev in body.get("events", []):
                ev["at"] = ev.get("at") or int(time.time() * 1000)
                self.events.append(ev)
            if isinstance(body.get("snapshot"), dict):
                self.snapshot = body["snapshot"]
            for seq, res in (body.get("results") or {}).items():
                self.results[int(seq)] = res
            self.lock.notify_all()

    def state(self, tail: int):
        with self.lock:
            age = time.time() - self.agent_seen_at if self.agent_seen_at else None
            return {
                "agent": self.agent_version,
                "agent_age_s": round(age, 1) if age is not None else None,
                "next_seq": self.next_seq(),
                "issued": [{"seq": c["seq"]} for c in self.commands[-20:]],
                "results": {str(k): v for k, v in sorted(self.results.items())[-20:]},
                "snapshot": self.snapshot,
                "events": list(self.events)[-tail:],
            }


class Handler(_serve.Handler):
    hub: Hub = None

    # --- plumbing ------------------------------------------------------------
    def _json(self, code: int, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # Signing our own replies lets the page tell this server from an impostor on the
        # same port, which matters because the page will act on what comes back.
        for k, v in sign_request(self.hub.secret, "RESPONSE", self.path.split("?")[0], body).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Headers",
                         "Range, Content-Type, X-Miku-Ts, X-Miku-Nonce, X-Miku-Sig")
        self.send_header("Access-Control-Expose-Headers",
                         "Content-Length, Content-Range, Accept-Ranges, "
                         "X-Miku-Ts, X-Miku-Nonce, X-Miku-Sig")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
        self.end_headers()

    def _read_body(self) -> bytes:
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _authenticate(self, method: str, body: bytes):
        """Returns None when the request is good, or a (code, message) to refuse with."""
        ts = self.headers.get("X-Miku-Ts", "")
        nonce = self.headers.get("X-Miku-Nonce", "")
        sig = self.headers.get("X-Miku-Sig", "")
        if not (ts and nonce and sig):
            return 401, "unsigned request"
        try:
            drift = abs(time.time() - int(ts))
        except ValueError:
            return 401, "bad timestamp"
        if drift > CLOCK_SKEW_S:
            return 401, f"timestamp is {int(drift)}s off; check the clock"
        path = self.path.split("?")[0]
        want = hmac.new(self.hub.secret, canonical(method, path, ts, nonce, body),
                        hashlib.sha256).hexdigest()
        if not hmac.compare_digest(want, sig):
            return 403, "bad signature"
        if not self.hub.check_nonce(nonce):
            return 409, "nonce replay"
        return None

    # --- API -----------------------------------------------------------------
    def do_GET(self):
        path = self.path.split("?")[0]
        if not path.startswith("/api/"):
            return super().do_GET()
        bad = self._authenticate("GET", b"")
        if bad:
            return self._json(bad[0], {"error": bad[1]})
        q = {}
        if "?" in self.path:
            for part in self.path.split("?", 1)[1].split("&"):
                if "=" in part:
                    k, v = part.split("=", 1)
                    q[k] = v
        if path == "/api/v1/ping":
            return self._json(200, {"ok": True, "server": "mikuos-control/1",
                                    "now": int(time.time() * 1000),
                                    "commands_known": sorted(COMMANDS)})
        if path == "/api/v1/poll":
            after = int(q.get("after") or 0)
            wait = min(float(q.get("wait") or POLL_WAIT_S), 60.0)
            return self._json(200, {"commands": self.hub.wait_for(after, wait),
                                    "now": int(time.time() * 1000)})
        if path == "/api/v1/state":
            return self._json(200, self.hub.state(int(q.get("tail") or 200)))
        return self._json(404, {"error": f"no such endpoint {path}"})

    def do_POST(self):
        path = self.path.split("?")[0]
        if not path.startswith("/api/"):
            return self._json(404, {"error": "POST is only for /api/"})
        body = self._read_body()
        bad = self._authenticate("POST", body)
        if bad:
            return self._json(bad[0], {"error": bad[1]})
        try:
            payload = json.loads(body or b"{}")
        except json.JSONDecodeError as e:
            return self._json(400, {"error": f"body is not JSON: {e}"})

        if path == "/api/v1/enqueue":
            return self._enqueue(payload)
        if path == "/api/v1/events":
            self.hub.ingest(payload)
            return self._json(200, {"ok": True})
        return self._json(404, {"error": f"no such endpoint {path}"})

    def _enqueue(self, payload):
        for field in ("payload_b64", "sig", "seq"):
            if field not in payload:
                return self._json(400, {"error": f"envelope is missing {field}"})
        try:
            raw = base64.b64decode(payload["payload_b64"], validate=True)
        except Exception as e:
            return self._json(400, {"error": f"payload_b64 is not base64: {e}"})
        want = hmac.new(self.hub.secret, CMD_PROTO.encode() + b"\n" + raw,
                        hashlib.sha256).hexdigest()
        if not hmac.compare_digest(want, payload["sig"]):
            return self._json(403, {"error": "command signature does not match its payload"})
        try:
            env = json.loads(raw)
        except json.JSONDecodeError as e:
            return self._json(400, {"error": f"signed payload is not JSON: {e}"})
        if env.get("seq") != payload["seq"]:
            return self._json(400, {"error": "seq outside the envelope disagrees with the one inside"})
        cmd = env.get("cmd")
        if cmd not in COMMANDS:
            return self._json(400, {"error": f"unknown command {cmd!r}; known: {', '.join(sorted(COMMANDS))}"})
        # The page enforces this too. Checking here as well means a mistake is refused
        # before it is ever in front of a device.
        if cmd == "select_action":
            act = (env.get("args") or {}).get("action")
            need = DESTRUCTIVE_ACTIONS.get(act)
            if need and env.get("confirm") != need:
                return self._json(400, {"error": f"{act} destroys user data; the envelope must "
                                                 f"carry confirm={need!r}"})
        try:
            seq = self.hub.enqueue({"seq": payload["seq"],
                                    "payload_b64": payload["payload_b64"],
                                    "sig": payload["sig"]})
        except ValueError as e:
            return self._json(409, {"error": str(e)})
        sys.stderr.write(f"[control] queued #{seq} {cmd} {env.get('args') or ''}\n")
        return self._json(200, {"ok": True, "seq": seq})

    def log_message(self, fmt, *args):
        # The page long-polls; logging every poll buries the interesting lines.
        if "/api/v1/poll" in (args[0] if args else ""):
            return
        super().log_message(fmt, *args)


def load_or_create_secret(path: str, regenerate: bool) -> bytes:
    if regenerate or not os.path.exists(path):
        secret = secrets.token_bytes(32)
        with open(path, "wb") as f:
            f.write(base64.urlsafe_b64encode(secret))
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        return secret
    with open(path, "rb") as f:
        return base64.urlsafe_b64decode(f.read().strip())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("USAGE")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--bind", default="127.0.0.1",
                    help="keep this on loopback: it is a channel that can brick a device, and "
                         "only localhost is a secure context for WebUSB without HTTPS")
    ap.add_argument("--images", help="directory to expose at /images/ (e.g. mikuos/out)")
    ap.add_argument("--secret-file", default=SECRET_PATH)
    ap.add_argument("--new-secret", action="store_true",
                    help="throw away the stored secret and mint a new one (invalidates open tabs)")
    args = ap.parse_args()

    secret = load_or_create_secret(args.secret_file, args.new_secret)
    os.chdir(HERE)
    Handler.images_dir = os.path.abspath(args.images) if args.images else None
    Handler.hub = Hub(secret)
    token = base64.urlsafe_b64encode(secret).decode().rstrip("=")

    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    base = f"http://localhost:{args.port}/"
    print(f"MikuOS installer           {base}")
    print(f"  with the control channel {base}#control={token}")
    print("  (the fragment never leaves the browser; without it the page is the public installer)")
    if Handler.images_dir:
        print(f"  /images/ -> {Handler.images_dir}")
    print(f"  secret: {args.secret_file} (0600)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
