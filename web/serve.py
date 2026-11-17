#!/usr/bin/env python3
"""Serve a LÖVR web build with the headers required by threaded/JSPI builds."""
import argparse
import http.server
import os
import socketserver


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", help="LÖVR build directory")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    os.chdir(args.directory)
    with socketserver.TCPServer((args.host, args.port), Handler) as server:
        print(f"serving {args.directory} on http://{args.host}:{args.port}")
        server.serve_forever()


if __name__ == "__main__":
    main()
