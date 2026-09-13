#!/usr/bin/env python3
"""Local dev server for the MikuOS web installer.

`python -m http.server` is NOT enough: it ignores HTTP Range requests, and the installer
streams the 5 GB super image in 63 MiB ranges. This server adds:
  * Range support (single byte-range, 206 / Content-Range / Accept-Ranges),
  * HEAD with Content-Length,
  * CORS headers (so a manifest hosted here can be used from another origin while testing),
  * an optional --images DIR mounted at /images/ (e.g. mikuos/out) so a manifest generated with
    `--base-url http://localhost:8000/images/` works without copying files.

WebUSB works on http://localhost without HTTPS.

    python3 tools/web-installer/serve.py --images mikuos/out --port 8000
    # then open http://localhost:8000/  (optionally ?manifest=release.json)
"""
import argparse
import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)$")


class Handler(SimpleHTTPRequestHandler):
    images_dir = None
    protocol_version = "HTTP/1.1"

    def translate_path(self, path):
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if self.images_dir and clean.startswith("/images/"):
            rel = os.path.normpath(clean[len("/images/"):]).lstrip("/")
            if rel.startswith(".."):
                return "/nonexistent"
            return os.path.join(self.images_dir, rel)
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Range")
        self.send_header("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
        self.end_headers()

    def do_GET(self):
        rng = self.headers.get("Range")
        if not rng:
            return super().do_GET()
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        m = RANGE_RE.match(rng.strip())
        if not m:
            self.send_error(416)
            return
        start_s, end_s = m.groups()
        if start_s == "":
            length = int(end_s)
            start, end = max(0, size - length), size - 1
        else:
            start = int(start_s)
            end = int(end_s) if end_s else size - 1
        if start >= size or end < start:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.end_headers()
            return
        end = min(end, size - 1)
        length = end - start + 1
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Length", str(length))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                buf = f.read(min(1024 * 1024, remaining))
                if not buf:
                    break
                self.wfile.write(buf)
                remaining -= len(buf)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--bind", default="127.0.0.1", help="use 127.0.0.1 (localhost is a secure context); 0.0.0.0 will NOT get WebUSB on other hosts without HTTPS")
    ap.add_argument("--images", help="directory to expose at /images/ (e.g. mikuos/out)")
    args = ap.parse_args()
    root = os.path.dirname(os.path.abspath(__file__))
    os.chdir(root)
    Handler.images_dir = os.path.abspath(args.images) if args.images else None
    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"MikuOS web installer: http://localhost:{args.port}/  (serving {root})")
    if Handler.images_dir:
        print(f"  /images/ -> {Handler.images_dir}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
