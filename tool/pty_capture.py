"""Run a command under a pseudo-terminal and keep everything it writes.

The terminal embedder draws with escape sequences and Kitty graphics rather
than to a window, so "what it rendered" is a byte stream, not a screenshot. It
also checks whether it has a terminal and behaves differently without one,
which is why this allocates a pty instead of a pipe.

A real file rather than a heredoc inside the workflow: the heredoc body sits at
the YAML block's indentation and arrived at Python mangled twice over, once as
leading whitespace on every line and once as an IndentationError after being
dedented. Neither failure said anything about the thing being tested.

Usage: pty_capture.py <output-path> <seconds> <command...>
"""

import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time


def main() -> int:
    if len(sys.argv) < 4:
        print(f"usage: {sys.argv[0]} <output> <seconds> <command...>")
        return 2

    output_path = sys.argv[1]
    seconds = float(sys.argv[2])
    command = sys.argv[3:]

    os.environ.setdefault("TERM", "xterm-256color")

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(command[0], command)

    # A forked pty has no window size, and a terminal application that reads
    # 0x0 does not degrade gracefully — the flt embedder sizes its frame buffer
    # from it and panics with a capacity overflow before drawing anything.
    # Every real terminal has dimensions; this one needs them too.
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))

    captured = bytearray()
    deadline = time.time() + seconds
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 1.0)
        if fd not in ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        captured += chunk

    with open(output_path, "wb") as handle:
        handle.write(bytes(captured))

    text = bytes(captured).decode("utf-8", "replace")
    print(f"captured bytes: {len(captured)}")
    # Started and rendered are different claims, and only the second one is
    # what this job exists to establish.
    raw = bytes(captured)
    # A capability query is not an image. The embedder asks whether the
    # terminal speaks Kitty graphics and falls back to ANSI when nothing
    # answers, so counting the query as "graphics present" reports the
    # question as though it were the answer.
    import re

    kitty = re.findall(rb"\x1b_G(.*?);(.*?)\x1b\\", raw, re.S)
    with_payload = [c for c, payload in kitty if payload]
    print(f"escape sequences present: {chr(27) + '[' in text}")
    print(f"kitty escapes: {len(kitty)} (with image payload: {len(with_payload)})")
    print(f"ansi colour writes: {text.count(chr(27) + '[38;2;')}")
    print(f"dart vm service line: {'Dart VM service' in text}")

    # Close the master first, then signal: a child still holding the slave can
    # keep this process alive past the deadline it was given.
    try:
        os.close(fd)
    except OSError:
        pass
    for signal_number in (15, 9):
        try:
            os.kill(pid, signal_number)
        except ProcessLookupError:
            break
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
