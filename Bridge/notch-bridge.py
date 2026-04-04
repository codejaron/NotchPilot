#!/usr/bin/env python3

import argparse
import json
import os
import socket
import sys
import uuid


DEFAULT_SOCKET_PATH = "/tmp/notchpilot.sock"


def read_stdin() -> str:
    return sys.stdin.read()


def read_line(sock: socket.socket) -> str:
    chunks: list[bytes] = []
    while True:
        byte = sock.recv(1)
        if not byte or byte == b"\n":
            break
        chunks.append(byte)
    return b"".join(chunks).decode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Forward hook payloads to NotchPilot over a Unix domain socket.")
    parser.add_argument("--host", required=True, choices=["claude", "codex"])
    parser.add_argument("--socket-path", default=os.environ.get("NOTCHPILOT_SOCKET_PATH", DEFAULT_SOCKET_PATH))
    parser.add_argument("--request-id", default=os.environ.get("NOTCHPILOT_REQUEST_ID", str(uuid.uuid4())))
    args = parser.parse_args()

    frame = {
        "host": args.host,
        "requestID": args.request_id,
        "rawJSON": read_stdin(),
    }

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(args.socket_path)
        client.sendall(json.dumps(frame).encode("utf-8") + b"\n")
        response = read_line(client)

    sys.stdout.write(response or "{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
