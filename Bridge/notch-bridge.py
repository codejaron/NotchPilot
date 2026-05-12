#!/usr/bin/env python3

import argparse
import json
import os
import plistlib
import socket
import subprocess
import sys
from typing import Optional
import uuid


NOTCHPILOT_BRIDGE_VERSION = 4
DEFAULT_SOCKET_PATH = "/tmp/notchpilot.sock"
TERMINAL_BUNDLE_IDS = {
    "Apple_Terminal": "com.apple.Terminal",
    "iTerm.app": "com.googlecode.iterm2",
    "vscode": "com.microsoft.VSCode",
    "WarpTerminal": "dev.warp.Warp-Stable",
}

# Map an agent CLI executable basename to a NotchPilot host identifier.
# These are the executables we recognise in the bridge's ancestor process chain
# so we can override `--host` (the hook command is installed as `--host claude`
# but Devin Local imports the same hooks file, so we need to detect the real
# parent and re-tag the frame).
AGENT_COMMAND_NAMES = {
    "claude": "claude",
    "codex": "codex",
    "devin": "devin",
}


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


def normalized(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def normalized_tty(value: Optional[str]) -> Optional[str]:
    tty = normalized(value)
    if tty is None or tty == "??":
        return None
    if tty.startswith("/dev/"):
        tty = tty.removeprefix("/dev/")
    return tty


def terminal_bundle_identifier_from_environment() -> Optional[str]:
    term_program = normalized(os.environ.get("TERM_PROGRAM"))
    if term_program in TERMINAL_BUNDLE_IDS:
        return TERMINAL_BUNDLE_IDS[term_program]
    if normalized(os.environ.get("ITERM_SESSION_ID")):
        return "com.googlecode.iterm2"
    lc_terminal = normalized(os.environ.get("LC_TERMINAL"))
    if lc_terminal and "iterm" in lc_terminal.lower():
        return "com.googlecode.iterm2"
    if lc_terminal and "warp" in lc_terminal.lower():
        return "dev.warp.Warp-Stable"
    return None


def read_process_row(pid: int) -> Optional[dict[str, object]]:
    try:
        result = subprocess.run(
            ["/bin/ps", "-p", str(pid), "-o", "pid=", "-o", "ppid=", "-o", "tty=", "-o", "command="],
            check=False,
            capture_output=True,
            text=True,
            timeout=0.5,
        )
    except Exception:
        return None

    line = result.stdout.strip()
    if result.returncode != 0 or not line:
        return None

    parts = line.split(None, 3)
    if len(parts) < 4:
        return None

    try:
        row_pid = int(parts[0])
        parent_pid = int(parts[1])
    except ValueError:
        return None

    return {
        "pid": row_pid,
        "ppid": parent_pid,
        "tty": normalized_tty(parts[2]),
        "command": parts[3],
    }


def process_tree() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    pid = os.getpid()
    seen: set[int] = set()

    while pid > 1 and pid not in seen:
        seen.add(pid)
        row = read_process_row(pid)
        if row is None:
            break
        rows.append(row)
        next_pid = row.get("ppid")
        if not isinstance(next_pid, int):
            break
        pid = next_pid

    return rows


def bundle_identifier_for_app_path(command: str) -> Optional[str]:
    marker = ".app/"
    marker_index = command.find(marker)
    if marker_index == -1:
        return None

    app_path = command[: marker_index + len(".app")]
    info_plist_path = os.path.join(app_path, "Contents", "Info.plist")
    try:
        with open(info_plist_path, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception:
        return None

    return normalized(plist.get("CFBundleIdentifier"))


def detect_agent_process(rows: list[dict[str, object]]) -> Optional[tuple[str, int]]:
    """Find the closest CLI agent process in the bridge's ancestor chain.

    Returns ``(agent_name, pid)`` or ``None``. ``agent_name`` is one of the
    values in :data:`AGENT_COMMAND_NAMES`. The first token of the ``command``
    column from ``ps`` is treated as the executable path; we match on its
    basename so that ``/Applications/Windsurf.app/.../devin/bin/devin acp``
    and a bare ``devin`` are both recognised.
    """
    for row in rows:
        command = row.get("command")
        if not isinstance(command, str) or not command:
            continue
        first_token = command.split(None, 1)[0]
        basename = os.path.basename(first_token).lower()
        agent_name = AGENT_COMMAND_NAMES.get(basename)
        if agent_name is None:
            continue
        pid = row.get("pid")
        if not isinstance(pid, int):
            continue
        return (agent_name, pid)
    return None


def maybe_inject_session_id(raw_json: str, agent_pid: int) -> str:
    """Ensure the hook payload exposes a stable ``session_id``.

    Claude Code populates ``session_id`` itself, so this is a no-op there.
    Devin Local's hook payloads do **not** include ``session_id``; without a
    fallback every tool call is parsed as a brand-new session because the
    NotchPilot side falls back to a per-invocation request UUID. We seed the
    field with the agent process PID, which stays stable for the lifetime of
    one Devin/Claude session.
    """
    if not raw_json or not raw_json.strip():
        return raw_json
    try:
        parsed = json.loads(raw_json)
    except (TypeError, ValueError):
        return raw_json
    if not isinstance(parsed, dict):
        return raw_json
    for key in ("session_id", "sessionId"):
        value = parsed.get(key)
        if isinstance(value, str) and value.strip():
            return raw_json
    parsed["session_id"] = f"notchpilot-agent-pid-{agent_pid}"
    return json.dumps(parsed)


def collect_origin(rows: Optional[list[dict[str, object]]] = None) -> dict[str, object]:
    if rows is None:
        rows = process_tree()
    terminal_identifier = next(
        (row["tty"] for row in rows if isinstance(row.get("tty"), str)),
        None,
    )
    terminal_bundle_identifier = terminal_bundle_identifier_from_environment()
    app_process_identifier: Optional[int] = None
    app_bundle_identifier: Optional[str] = None

    for row in rows:
        command = row.get("command")
        if not isinstance(command, str):
            continue
        bundle_identifier = bundle_identifier_for_app_path(command)
        if bundle_identifier:
            app_process_identifier = row.get("pid") if isinstance(row.get("pid"), int) else None
            app_bundle_identifier = bundle_identifier
            break

    bundle_identifier = terminal_bundle_identifier or app_bundle_identifier
    process_identifier = app_process_identifier if app_bundle_identifier else None

    origin: dict[str, object] = {}
    if process_identifier is not None:
        origin["processIdentifier"] = process_identifier
    if bundle_identifier:
        origin["bundleIdentifier"] = bundle_identifier
    if terminal_identifier:
        origin["terminalIdentifier"] = terminal_identifier
    return origin


def main() -> int:
    parser = argparse.ArgumentParser(description="Forward hook payloads to NotchPilot over a Unix domain socket.")
    parser.add_argument("--host", required=True, choices=["claude", "codex", "devin"])
    parser.add_argument("--socket-path", default=os.environ.get("NOTCHPILOT_SOCKET_PATH", DEFAULT_SOCKET_PATH))
    parser.add_argument("--request-id", default=os.environ.get("NOTCHPILOT_REQUEST_ID", str(uuid.uuid4())))
    args = parser.parse_args()

    raw_json = read_stdin()
    rows = process_tree()
    detected = detect_agent_process(rows)

    effective_host = args.host
    agent_pid: Optional[int] = None
    if detected is not None:
        agent_name, agent_pid = detected
        # Override host only when we have stronger evidence than the static
        # --host flag. The hook command is hard-installed as `--host claude`
        # in ~/.claude/settings.json, but Devin Local reuses that same hooks
        # file. When the real ancestor is `devin`, re-tag the frame so the
        # Swift side routes it to the Devin display branch.
        if agent_name == "devin":
            effective_host = "devin"

    if agent_pid is not None:
        raw_json = maybe_inject_session_id(raw_json, agent_pid)

    frame = {
        "host": effective_host,
        "requestID": args.request_id,
        "rawJSON": raw_json,
    }
    origin = collect_origin(rows=rows)
    if origin:
        frame["origin"] = origin

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(args.socket_path)
        client.sendall(json.dumps(frame).encode("utf-8") + b"\n")
        response = read_line(client)

    sys.stdout.write(response or "{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
