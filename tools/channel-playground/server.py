#!/usr/bin/env python3
"""
Notch Channel Playground — a local web UI for exercising the Notch Channel by hand.

    python3 tools/channel-playground/server.py            # serves http://127.0.0.1:8765
    python3 tools/channel-playground/server.py --port 9000 --no-open

Why a server and not just a page: the channel refuses any request that carries an `Origin` header
(403 forbidden_origin), which is every request a browser makes. So the page talks to this server,
and this server — not a browser — talks to the channel. It reads the port and token from the
discovery file the app publishes, so there is nothing to configure.

Standard library only. Listens on 127.0.0.1.

This server holds the channel's token, so it guards itself the way the channel does. It answers only
requests addressed to itself by name (no DNS rebinding), takes `/api/send` only as JSON from its own
page (a cross-site form or fetch cannot reach it), never hands the token to the browser, and sends
only to the port the discovery file names.
"""

import argparse
import http.client
import json
import os
import sys
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTAINER = Path.home() / "Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch"
DISCOVERY_CANDIDATES = [
    CONTAINER / "notch-channel.json",
    CONTAINER / "reminder-channel.json",
    # An unsandboxed build (CODE_SIGNING_ALLOWED=NO) writes outside the container.
    Path.home() / "Library/Application Support/NotBoringNotch/notch-channel.json",
]


def read_discovery(override):
    candidates = [Path(override)] if override else DISCOVERY_CANDIDATES
    for path in candidates:
        try:
            data = json.loads(path.read_text())
            return {"path": str(path), "port": int(data["port"]), "token": data["token"],
                    "modified": path.stat().st_mtime}
        except (OSError, ValueError, KeyError):
            continue
    return None


class Handler(BaseHTTPRequestHandler):
    discovery_override = None

    def _own_origins(self):
        port = self.server.server_address[1]
        return {"http://127.0.0.1:%d" % port, "http://localhost:%d" % port}

    def _addressed_to_us(self):
        """The Host header names this server. A rebound DNS name would carry its own name here."""
        host = self.headers.get("Host", "")
        return "http://" + host in self._own_origins()

    def log_message(self, fmt, *args):  # quieter than the default
        sys.stderr.write("· %s\n" % (fmt % args))

    def _send(self, status, body, content_type="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self._addressed_to_us():
            self._send(403, {"error": "wrong host"})
            return
        if self.path in ("/", "/index.html"):
            self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        elif self.path == "/api/discovery":
            d = read_discovery(self.discovery_override)
            if d is None:
                self._send(200, {"found": False, "searched": [str(p) for p in DISCOVERY_CANDIDATES]})
            else:
                # The page shows where the channel is; the token stays here.
                self._send(200, {"found": True, "path": d["path"], "port": d["port"],
                                 "modified": d["modified"]})
        else:
            self._send(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/api/send":
            self._send(404, {"error": "not_found"})
            return
        # This route forwards with the real token, so only this server's own page may use it.
        # Requiring JSON makes a cross-site request preflight, which this server never answers;
        # checking Origin and Host covers the rest.
        origin = self.headers.get("Origin")
        content_type = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if not self._addressed_to_us() or (origin is not None and origin not in self._own_origins()):
            self._send(403, {"error": "forbidden"})
            return
        if content_type != "application/json":
            self._send(415, {"error": "json only"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            spec = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            self._send(400, {"error": "bad spec"})
            return

        d = read_discovery(self.discovery_override)
        if d is None:
            self._send(200, {"ok": False, "error": "No discovery file. Is the app running with the channel on?"})
            return

        method = spec.get("method", "POST")
        path = spec.get("path", "/v2/notifications")
        body = spec.get("body")
        headers = {}
        # token: "auto" (default) uses the discovery token, null sends none, a string sends that.
        token = spec.get("token", "auto")
        if token == "auto":
            token = d["token"]
        if token is not None:
            headers["Authorization"] = "Bearer %s" % token
        payload = None
        if body is not None:
            payload = body.encode() if isinstance(body, str) else json.dumps(body).encode()
            headers["Content-Type"] = spec.get("contentType", "application/json")
        for k, v in (spec.get("headers") or {}).items():
            headers[k] = v

        started = time.perf_counter()
        try:
            # Always the discovered port: the token is the channel's, and goes nowhere else.
            conn = http.client.HTTPConnection("127.0.0.1", d["port"], timeout=5)
            conn.request(method, path, body=payload, headers=headers)
            resp = conn.getresponse()
            raw = resp.read().decode(errors="replace")
            status = resp.status
            conn.close()
        except OSError as e:
            self._send(200, {"ok": False, "error": "Could not reach the channel: %s" % e})
            return
        elapsed = round((time.perf_counter() - started) * 1000, 1)
        try:
            parsed = json.loads(raw)
        except ValueError:
            parsed = raw
        self._send(200, {"ok": True, "status": status, "body": parsed, "ms": elapsed,
                         "request": {"method": method, "path": path, "headers": {
                             k: ("Bearer •••" if k == "Authorization" and token == d["token"] else v)
                             for k, v in headers.items()}}})


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--discovery", help="path to a discovery file, if not the default")
    parser.add_argument("--no-open", action="store_true", help="do not open a browser")
    args = parser.parse_args()

    Handler.discovery_override = args.discovery
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = "http://127.0.0.1:%d" % args.port
    print("Notch Channel Playground on %s  (Ctrl-C to stop)" % url)
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
