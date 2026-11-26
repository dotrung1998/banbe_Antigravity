#!/usr/bin/env python3
"""Serve one Quartz build on a loopback port.

Clean URLs: /foo -> foo.html, /foo/ -> foo/index.html, miss -> 404.html (404).
No directory listings. Stdlib only.
"""
from __future__ import annotations

import argparse
import http.server
import mimetypes
import os
import posixpath
import sys
import urllib.parse


class Handler(http.server.BaseHTTPRequestHandler):
    root = "."

    def log_message(self, fmt: str, *args) -> None:
        sys.stdout.write("%s %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()

    def resolve(self, url_path: str) -> tuple[str, int, bool]:
        """Return (filesystem path, status, is_404_fallback)."""
        path = urllib.parse.unquote(urllib.parse.urlsplit(url_path).path)
        path = posixpath.normpath(path)
        relative = path.lstrip("/")
        if relative in ("", "."):
            relative = "index.html"
        elif path.endswith("/"):
            relative = posixpath.join(relative, "index.html")

        candidate = os.path.realpath(os.path.join(self.root, relative))
        root = os.path.realpath(self.root)
        if candidate != root and not candidate.startswith(root + os.sep):
            return "", 403, False

        candidates = [candidate]
        if not path.endswith("/"):
            candidates.append(candidate + ".html")
        candidates.append(os.path.join(candidate, "index.html"))

        for item in candidates:
            if os.path.isfile(item):
                return item, 200, False

        not_found = os.path.join(root, "404.html")
        if os.path.isfile(not_found):
            return not_found, 404, True
        return "", 404, True

    def send_file(self, path: str, status: int) -> None:
        try:
            with open(path, "rb") as handle:
                body = handle.read()
        except OSError:
            self.send_error(404)
            return
        ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype in ("application/javascript", "application/json"):
            ctype += "; charset=utf-8"
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self) -> None:
        path, status, fallback = self.resolve(self.path)
        if status == 403:
            self.send_error(403)
            return
        if fallback and not path:
            self.send_error(404)
            return
        self.send_file(path, status)

    def do_HEAD(self) -> None:
        self.do_GET()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, default=8082)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()

    if not os.path.isdir(args.root):
        parser.error(f"root is not a directory: {args.root}")

    Handler.root = args.root
    server = http.server.ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"serving {args.root} on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
