#!/usr/bin/env python3
"""Entry point: run from anywhere, no install step."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from history.cli import main

if __name__ == "__main__":
    sys.exit(main())
