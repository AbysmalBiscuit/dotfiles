import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "apply_updates", ROOT / ".chezmoiscripts/run_after_80-apply_post.py"
)
assert SPEC is not None
assert SPEC.loader is not None
hook = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hook)


class ApplyUpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.marker = self.root / "calls"

    def update(self, now: float, fail: bool = False) -> None:
        command = [
            sys.executable,
            "-c",
            "from pathlib import Path; "
            f"p = Path({str(self.marker)!r}); "
            "p.write_text((p.read_text() if p.exists() else '') + 'x'); "
            f"raise SystemExit({3 if fail else 0})",
        ]
        with (
            patch.object(hook, "HAS_FILE", self.root / "has.toml"),
            patch.object(
                hook,
                "load_toml",
                side_effect=[{"claude": True}, {"tools": [{"name": "claude", "update": command}]}],
            ),
            patch("time.time", return_value=now),
        ):
            hook.update_cli_tools()

    def test_successful_updates_are_spaced_three_days_apart(self) -> None:
        self.update(1000)
        self.update(1000 + 3 * 24 * 60 * 60 - 1)
        assert self.marker.read_text() == "x"
        self.update(1000 + 3 * 24 * 60 * 60)
        assert self.marker.read_text() == "xx"

    def test_failure_can_retry_on_the_next_apply(self) -> None:
        self.update(1000, fail=True)
        self.update(1001)
        self.update(1002)
        assert self.marker.read_text() == "xx"


if __name__ == "__main__":
    unittest.main()
