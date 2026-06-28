#!/usr/bin/env python3
# LAB ARTIFACT — fake attack for hardening demonstration only
# ============================================================================
# local-exfil-server.py — Minimal HTTP server for exfiltration demonstration
# ============================================================================
#
# Binds ONLY to 127.0.0.1:8888 (localhost). Logs all POSTed data to stdout.
# This is the local exfil sink used by attack 05 (exfiltration).
#
# Usage: python3 attacks/local-exfil-server.py
# Stop:  Ctrl+C
#
# SAFETY: This server binds exclusively to 127.0.0.1. It is not reachable
# from outside the machine. It never touches any third-party system.
# ============================================================================

import http.server
import sys
from datetime import datetime, timezone


HOST = "127.0.0.1"  # localhost ONLY — never bind to 0.0.0.0
PORT = 8888


class ExfilHandler(http.server.BaseHTTPRequestHandler):
    """Logs all incoming requests and their bodies to stdout."""

    def _log_request(self, method: str) -> None:
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        content_length = int(self.headers.get("Content-Length", 0))
        body = ""
        if content_length > 0:
            body = self.rfile.read(content_length).decode("utf-8", errors="replace")

        print(f"\n{'=' * 60}")
        print(f"[EXFIL RECEIVED] {timestamp}")
        print(f"  Method:       {method}")
        print(f"  Path:         {self.path}")
        print(f"  Client:       {self.client_address[0]}:{self.client_address[1]}")
        print(f"  Content-Type: {self.headers.get('Content-Type', 'N/A')}")
        print(f"  Body length:  {content_length}")
        if body:
            print(f"  Body:         {body}")
        print(f"{'=' * 60}")
        sys.stdout.flush()

        # Send 200 OK response
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"received\n")

    def do_POST(self) -> None:
        self._log_request("POST")

    def do_GET(self) -> None:
        self._log_request("GET")

    def do_PUT(self) -> None:
        self._log_request("PUT")

    def log_message(self, format: str, *args) -> None:
        """Suppress default stderr logging — we log to stdout instead."""
        pass


def main() -> None:
    print(f"{'=' * 60}")
    print(f"  Local Exfil Sink")
    print(f"  LAB ARTIFACT — for hardening demonstration only")
    print(f"  Listening on {HOST}:{PORT}")
    print(f"  Press Ctrl+C to stop")
    print(f"{'=' * 60}")
    sys.stdout.flush()

    server = http.server.HTTPServer((HOST, PORT), ExfilHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[exfil-server] Shutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
