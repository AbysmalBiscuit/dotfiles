import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "hooks/update_release.py"
SPEC = importlib.util.spec_from_file_location("update_release", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class ReleaseUpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.destination = Path(temporary.name)
        self.version = "0.1.0"

    def update(self, tool: str, fail: bool = False) -> int:
        suffix = ".exe" if os.name == "nt" else ""
        names = [tool] if tool == "mcpls" else ["devkit", "devkitd"]
        names = [name + suffix for name in names]
        variable = f"{tool.upper()}_UNMANAGED_INSTALL"
        if os.name == "nt":
            body = f"$ErrorActionPreference = 'Stop'\n$dest = $env:{variable}\n"
            body += "New-Item -ItemType Directory -Force -Path $dest | Out-Null\n"
            body += "".join(
                f"Set-Content -NoNewline -Path (Join-Path $dest '{name}') -Value 'new binary'\n"
                for name in names
            )
        else:
            body = f'#!/bin/sh\nset -eu\ndest="${variable}"\nmkdir -p "$dest"\n'
            body += "".join(f'printf "new binary" > "$dest/{name}"\n' for name in names)
        body += "exit 3\n" if fail else "exit 0\n"
        which = shutil.which

        def locate(name: str) -> str | None:
            return str(self.destination / (tool + suffix)) if name == tool else which(name)

        run = subprocess.run

        def execute(argv: list[str], **kwargs):
            if argv[-1:] == ["--version"]:
                return subprocess.CompletedProcess(argv, 0, f"{tool} {self.version}\n", "")
            return run(argv, **kwargs)

        def download(url: str, **_kwargs: object) -> io.BytesIO:
            if url.endswith("/releases/latest"):
                return io.BytesIO(json.dumps({"tag_name": "v0.2.0"}).encode())
            return io.BytesIO(body.encode())

        with (
            patch("sys.argv", ["update_release.py", tool]),
            patch("shutil.which", side_effect=locate),
            patch("urllib.request.urlopen", side_effect=download),
            patch("subprocess.run", side_effect=execute),
            redirect_stdout(io.StringIO()),
        ):
            return updater.main()

    def test_staged_release_updates_binary_and_devkit_aliases(self) -> None:
        suffix = ".exe" if os.name == "nt" else ""
        for tool in ("devkit", "mcpls"):
            with self.subTest(tool=tool):
                executable = self.destination / (tool + suffix)
                executable.write_bytes(b"old binary")
                assert self.update(tool) == 0
                assert executable.read_bytes() == b"new binary"
        assert (self.destination / ("devkitd" + suffix)).read_bytes() == b"new binary"
        assert (self.destination / ("docm" + suffix)).read_bytes() == b"new binary"

    def test_failed_installer_preserves_current_binary(self) -> None:
        executable = self.destination / ("mcpls.exe" if os.name == "nt" else "mcpls")
        executable.write_bytes(b"old binary")
        assert self.update("mcpls", fail=True) == 3
        assert executable.read_bytes() == b"old binary"

    def test_locked_executable_is_renamed_aside(self) -> None:
        executable = self.destination / ("mcpls.exe" if os.name == "nt" else "mcpls")
        executable.write_bytes(b"running binary")
        replace = Path.replace

        def locked_replace(source: Path, target: Path) -> Path:
            if target == executable and target.exists():
                raise PermissionError("executable in use")
            return replace(source, target)

        with patch.object(Path, "replace", locked_replace):
            assert self.update("mcpls") == 0
        assert executable.read_bytes() == b"new binary"
        backup = executable.with_name("mcpls_old" + executable.suffix)
        assert backup.read_bytes() == b"running binary"

    def test_matching_and_newer_builds_are_not_replaced(self) -> None:
        for tool in ("devkit", "mcpls"):
            for version in ("0.2.0", "0.3.0", "0.3.0-dev.1", "0.2.0+source.123"):
                with self.subTest(tool=tool, version=version):
                    executable = self.destination / (tool + (".exe" if os.name == "nt" else ""))
                    executable.write_bytes(b"source build")
                    self.version = version
                    assert self.update(tool) == 0
                    assert executable.read_bytes() == b"source build"

    def test_same_version_prerelease_upgrades_to_stable(self) -> None:
        executable = self.destination / ("mcpls.exe" if os.name == "nt" else "mcpls")
        executable.write_bytes(b"prerelease")
        self.version = "0.2.0-rc.1"
        assert self.update("mcpls") == 0
        assert executable.read_bytes() == b"new binary"

    def test_unknown_build_version_is_not_replaced(self) -> None:
        executable = self.destination / ("mcpls.exe" if os.name == "nt" else "mcpls")
        executable.write_bytes(b"custom build")
        self.version = "development"
        assert self.update("mcpls") == 1
        assert executable.read_bytes() == b"custom build"


if __name__ == "__main__":
    unittest.main()
