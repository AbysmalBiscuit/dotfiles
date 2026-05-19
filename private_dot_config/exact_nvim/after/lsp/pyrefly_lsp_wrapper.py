import subprocess
import sys
import threading
import re

proc = subprocess.Popen(
    ["pyrefly", "lsp"],
    stdin=sys.stdin.buffer,
    stdout=sys.stdout.buffer,
    stderr=subprocess.PIPE,
)


def filter_stderr():
    for line in proc.stderr:
        if not re.match(rb"^\s*INFO", line):
            sys.stderr.buffer.write(line)
            sys.stderr.buffer.flush()


threading.Thread(target=filter_stderr, daemon=True).start()
sys.exit(proc.wait())
