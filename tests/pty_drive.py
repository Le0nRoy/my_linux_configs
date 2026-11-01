#!/usr/bin/env python3
"""Drive an interactive shell through a real pseudo-terminal.

Usage: pty_drive.py <steps_file> <transcript_file> -- <command> [args...]

Each line of <steps_file> is one step:
    send <text>     write <text> to the terminal; Python escapes are
                    decoded (\\t = Tab, \\r = Enter, \\x04 = Ctrl+D, ...)
    wait <regex>    block until <regex> matches output read since the
                    previous wait (ANSI escapes stripped)
    mark <name>     write "<<MARK name>>" into the transcript
    tabuntil <regex>
                    press Tab, wait for the shell's response, and repeat
                    (at most MAX_TABS times) until <regex> matches. One Tab
                    per read: readline inserts a literal Tab when more input
                    is already queued (paste detection).
    eof             block until the shell exits

The ANSI-stripped transcript is written to <transcript_file>. Exit status:
0 all steps done, 3 a wait/eof timed out (step reported on stderr), 2 usage.
The child's exit status is appended to the transcript as "<<EXIT n>>".
"""

import codecs
import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time

STEP_TIMEOUT_SECONDS = 15
MAX_TABS = 4
# A Tab's response is complete once output pauses this long.
QUIET_SECONDS = 0.3
READ_CHUNK_BYTES = 4096
TERMINAL_ROWS = 60
TERMINAL_COLS = 220
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[\]_P][^\x07\x1b]*(\x07|\x1b\\)|\x1b[=>()][0-9A-Za-z]?|\r")


def strip_ansi(text):
    return ANSI_RE.sub("", text)


def read_available(fd, deadline):
    """Return decoded output available before deadline, or None at EOF."""
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return ""
    ready, _, _ = select.select([fd], [], [], remaining)
    if not ready:
        return ""
    try:
        data = os.read(fd, READ_CHUNK_BYTES)
    except OSError:
        return None
    if not data:
        return None
    return data.decode("utf-8", "replace")


def main(argv):
    if len(argv) < 5 or argv[3] != "--":
        print(__doc__, file=sys.stderr)
        return 2
    steps_file, transcript_file, command = argv[1], argv[2], argv[4:]
    with open(steps_file, encoding="utf-8") as handle:
        steps = [line.rstrip("\n") for line in handle if line.strip()]

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(command[0], command)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", TERMINAL_ROWS, TERMINAL_COLS, 0, 0))

    transcript = []
    pending = ""
    eof = False
    status = 0
    try:
        for index, step in enumerate(steps, 1):
            verb, _, arg = step.partition(" ")
            if verb == "send":
                os.write(fd, codecs.decode(arg, "unicode_escape").encode("utf-8"))
            elif verb == "mark":
                transcript.append(f"\n<<MARK {arg}>>\n")
            elif verb == "tabuntil":
                pattern = re.compile(arg)
                deadline = time.monotonic() + STEP_TIMEOUT_SECONDS
                for _ in range(MAX_TABS):
                    os.write(fd, b"\t")
                    chunk = read_available(fd, deadline)
                    while chunk:
                        pending += chunk
                        transcript.append(strip_ansi(chunk))
                        chunk = read_available(fd, min(deadline, time.monotonic() + QUIET_SECONDS))
                    if chunk is None:
                        eof = True
                        break
                    if pattern.search(strip_ansi(pending)):
                        break
                if not pattern.search(strip_ansi(pending)):
                    print(f"step {index} ({step}): no match after {MAX_TABS} tabs", file=sys.stderr)
                    status = 3
                    return status
                pending = ""
            elif verb in ("wait", "eof"):
                pattern = re.compile(arg) if verb == "wait" else None
                deadline = time.monotonic() + STEP_TIMEOUT_SECONDS
                while True:
                    if pattern is not None and pattern.search(strip_ansi(pending)):
                        pending = ""
                        break
                    if eof:
                        if pattern is None:
                            break
                        print(f"step {index} ({step}): shell exited first", file=sys.stderr)
                        status = 3
                        return status
                    if time.monotonic() >= deadline:
                        print(f"step {index} ({step}): timed out", file=sys.stderr)
                        status = 3
                        return status
                    chunk = read_available(fd, deadline)
                    if chunk is None:
                        eof = True
                        continue
                    pending += chunk
                    transcript.append(strip_ansi(chunk))
            else:
                print(f"step {index}: unknown verb {verb}", file=sys.stderr)
                status = 2
                return status
    finally:
        if not eof:
            try:
                os.kill(pid, 9)
            except ProcessLookupError:
                pass
        _, wait_status = os.waitpid(pid, 0)
        transcript.append(f"\n<<EXIT {os.waitstatus_to_exitcode(wait_status)}>>\n")
        os.close(fd)
        with open(transcript_file, "w", encoding="utf-8") as handle:
            handle.write("".join(transcript))
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
