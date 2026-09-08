#!/usr/bin/env python3
"""Publish SVD NIM endpoint metadata and hold CDSW_APP_PORT for health checks."""

from __future__ import annotations

import argparse
import http.server
import os
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.nim_runtime import publish_nim_endpoint, wait_for_nim_ready  # noqa: E402


def _serve_port(port: int) -> None:
    handler = http.server.BaseHTTPRequestHandler

    class HealthHandler(handler):
        def do_GET(self):  # noqa: N802
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, *_args):  # noqa: ANN002
            return

    server = http.server.HTTPServer(("127.0.0.1", port), HealthHandler)
    server.serve_forever()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--grpc-port", type=int, default=8001)
    parser.add_argument("--http-port", type=int, default=8000)
    parser.add_argument("--app-port", type=int, default=8100)
    args = parser.parse_args()

    def publisher() -> None:
        try:
            wait_for_nim_ready(args.http_port, args.grpc_port)
            publish_nim_endpoint(grpc_port=args.grpc_port, http_port=args.http_port)
            print("Published SVD endpoint metadata", flush=True)
        except Exception as exc:  # noqa: BLE001
            print(f"Endpoint publish failed: {exc}", flush=True)

    threading.Thread(target=publisher, daemon=True).start()
    time.sleep(2)
    _serve_port(args.app_port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
