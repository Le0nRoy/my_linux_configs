#!/usr/bin/env python3
# Streaming stdin filter. Extracts OSC 52 clipboard payloads (ESC ] 52 ;
# [cps0-7]* ; <base64> ( BEL | ESC \ )) and pipes decoded bytes to pbcopy.
# Installed via tmux pipe-pane on each pane to bridge OSC 52 writes to
# macOS Terminal.app, which has no native OSC 52 handler.
import base64
import re
import subprocess
import sys

PATTERN = re.compile(rb"\x1b\]52;[cps0-7]*;([A-Za-z0-9+/=]*)(?:\x07|\x1b\\)")
MAX_BUF = 65536
CHUNK = 4096


def main() -> None:
    stream = sys.stdin.buffer
    buf = b""
    while True:
        chunk = stream.read1(CHUNK) if hasattr(stream, "read1") else stream.read(CHUNK)
        if not chunk:
            break
        buf += chunk
        while True:
            match = PATTERN.search(buf)
            if not match:
                break
            payload = match.group(1)
            buf = buf[match.end():]
            try:
                decoded = base64.b64decode(payload, validate=False)
            except Exception:
                continue
            subprocess.run(["pbcopy"], input=decoded, check=False)
        if len(buf) > MAX_BUF:
            # ponytail: drop stale prefix if no match for 64 KiB — a dangling
            # ESC ] 52 ; would otherwise pin memory until the pane closed.
            buf = buf[-CHUNK:]


if __name__ == "__main__":
    main()
