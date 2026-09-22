import ctypes
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from contextlib import ExitStack, redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "hooks/update_herdr.py"
SPEC = importlib.util.spec_from_file_location("herdr_update", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class HerdrUpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.output = io.StringIO()

    def update(
        self,
        payload: bytes,
        system: str = "Linux",
        machine: str = "x86_64",
        checksum: str | None = None,
    ) -> int:
        windows = system == "Windows"
        executable = self.directory / ("herdr.exe" if windows else "herdr")
        target = {
            ("Linux", "x86_64"): "linux-x86_64",
            ("Linux", "aarch64"): "linux-aarch64",
            ("Darwin", "arm64"): "macos-aarch64",
            ("Darwin", "x86_64"): "macos-x86_64",
            ("Windows", "AMD64"): "windows-x86_64",
            ("Windows", "ARM64"): "windows-x86_64",
        }[(system, machine)]
        url = f"https://github.com/herdrdev/herdr/releases/download/preview-test/herdr-{target}"
        asset = {"url": url, "sha256": checksum or hashlib.sha256(payload).hexdigest()}
        if windows:
            asset["format"] = "zip"
        manifest = {"channel": "preview", "build_id": "test", "assets": {target: asset}}
        responses = {
            "https://herdr.dev/preview.json": json.dumps(manifest).encode(),
            url: payload,
        }

        def download(request: str, **_kwargs: object) -> io.BytesIO:
            return io.BytesIO(responses[request])

        with ExitStack() as stack:
            stack.enter_context(patch("shutil.which", return_value=str(executable)))
            stack.enter_context(patch("platform.system", return_value=system))
            stack.enter_context(patch("platform.machine", return_value=machine))
            stack.enter_context(patch("urllib.request.urlopen", side_effect=download))
            stack.enter_context(patch("sys.argv", ["herdr-update"]))
            stack.enter_context(redirect_stdout(self.output))
            stack.enter_context(redirect_stderr(self.output))
            return updater.main()

    def test_platform_download_preserves_old_executable_and_skips_repeat(self) -> None:
        for system, machine in (
            ("Linux", "x86_64"),
            ("Linux", "aarch64"),
            ("Darwin", "arm64"),
            ("Darwin", "x86_64"),
        ):
            with self.subTest(system=system, machine=machine):
                executable = self.directory / "herdr"
                executable.write_bytes(b"old executable")
                backup = self.directory / "herdr_old"
                backup.unlink(missing_ok=True)
                assert self.update(b"new executable", system, machine) == 0
                assert executable.read_bytes() == b"new executable"
                assert backup.read_bytes() == b"old executable"
                inode = executable.stat().st_ino
                assert self.update(b"new executable", system, machine) == 0
                assert executable.stat().st_ino == inode
                assert backup.read_bytes() == b"old executable"

    def test_another_update_keeps_the_first_backup(self) -> None:
        executable = self.directory / "herdr"
        executable.write_bytes(b"running version")
        assert self.update(b"first update") == 0
        assert self.update(b"second update") == 0
        assert executable.read_bytes() == b"second update"
        assert (self.directory / "herdr_old").read_bytes() == b"running version"
        assert (self.directory / "herdr_old_1").read_bytes() == b"first update"

    def test_checksum_failure_leaves_installation_untouched(self) -> None:
        executable = self.directory / "herdr"
        executable.write_bytes(b"running version")
        assert self.update(b"corrupt download", checksum="0" * 64) == 1
        assert executable.read_bytes() == b"running version"
        assert not (self.directory / "herdr_old").exists()

    def windows_archive(self) -> bytes:
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            for name, content in {
                "herdr.exe": b"new executable",
                "conpty/conpty.dll": b"new DLL",
                "conpty/x64/OpenConsole.exe": b"new x64 host",
                "conpty/arm64/OpenConsole.exe": b"new arm64 host",
                "conpty/herdr-conpty.json": b"{}",
                "THIRD-PARTY-NOTICES/license.txt": b"license",
            }.items():
                archive.writestr(name, content)
        return stream.getvalue()

    def test_windows_bundle_preserves_executable_and_loaded_dll(self) -> None:
        for machine in ("AMD64", "ARM64"):
            with self.subTest(machine=machine):
                executable = self.directory / "herdr.exe"
                executable.write_bytes(b"old executable")
                dll = self.directory / "conpty/conpty.dll"
                dll.parent.mkdir(exist_ok=True)
                dll.write_bytes(b"loaded DLL")
                assert self.update(self.windows_archive(), "Windows", machine) == 0
                assert executable.read_bytes() == b"new executable"
                assert (self.directory / "herdr_old.exe").read_bytes() == b"old executable"
                assert dll.read_bytes() == b"new DLL"
                assert (self.directory / "conpty_old/conpty.dll").read_bytes() == b"loaded DLL"
                assert {
                    path.relative_to(dll.parent).as_posix()
                    for path in dll.parent.rglob("*")
                    if path.is_file()
                } == {
                    "conpty.dll",
                    "x64/OpenConsole.exe",
                    "arm64/OpenConsole.exe",
                    "herdr-conpty.json",
                }
                assert (
                    self.directory / "conpty/x64/OpenConsole.exe"
                ).read_bytes() == b"new x64 host"

    def test_failed_activation_restores_old_executable(self) -> None:
        executable = self.directory / "herdr"
        executable.write_bytes(b"old executable")
        rename = Path.rename

        def fail_install(source: Path, target: Path) -> Path:
            if source.name == "herdr" and source.parent != self.directory:
                raise PermissionError("replacement blocked")
            return rename(source, target)

        with patch.object(Path, "rename", fail_install):
            assert self.update(b"new executable") == 1
        assert executable.read_bytes() == b"old executable"

    @unittest.skipIf(os.name == "nt", "uses the Unix sleep executable")
    def test_running_process_survives_replacement(self) -> None:
        executable = self.directory / "herdr"
        shutil.copy2("/bin/sleep", executable)
        original = executable.read_bytes()
        with subprocess.Popen([str(executable), "30"]) as process:
            try:
                assert self.update(b"new executable") == 0
                assert process.poll() is None
                assert (self.directory / "herdr_old").read_bytes() == original
            finally:
                process.terminate()
                process.wait(timeout=5)

    def test_windows_activation_failure_rolls_back_companion_files(self) -> None:
        executable = self.directory / "herdr.exe"
        executable.write_bytes(b"old executable")
        dll = self.directory / "conpty/conpty.dll"
        dll.parent.mkdir()
        dll.write_bytes(b"loaded DLL")
        rename = Path.rename

        def fail_install(source: Path, target: Path) -> Path:
            if source.name == "herdr.exe" and source.parent != self.directory:
                raise PermissionError("replacement blocked")
            return rename(source, target)

        with patch.object(Path, "rename", fail_install):
            assert self.update(self.windows_archive(), "Windows", "AMD64") == 1
        assert executable.read_bytes() == b"old executable"
        assert dll.read_bytes() == b"loaded DLL"
        assert not (self.directory / "conpty/x64/OpenConsole.exe").exists()

    def test_incomplete_windows_archive_leaves_installation_untouched(self) -> None:
        executable = self.directory / "herdr.exe"
        executable.write_bytes(b"old executable")
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            archive.writestr("herdr.exe", b"new executable")
        assert self.update(stream.getvalue(), "Windows", "AMD64") == 1
        assert executable.read_bytes() == b"old executable"
        assert not (self.directory / "herdr_old.exe").exists()

    @unittest.skipUnless(os.name == "nt", "requires Windows executable locking")
    def test_windows_running_executable_survives_replacement(self) -> None:
        executable = self.directory / "herdr.exe"
        shutil.copy2(Path(os.environ["SYSTEMROOT"]) / "System32/ping.exe", executable)
        original = executable.read_bytes()
        with subprocess.Popen(
            [str(executable), "-n", "30", "127.0.0.1"], stdout=subprocess.DEVNULL
        ) as process:
            try:
                assert self.update(self.windows_archive(), "Windows", "AMD64") == 0
                assert process.poll() is None
                assert (self.directory / "herdr_old.exe").read_bytes() == original
            finally:
                process.terminate()
                process.wait(timeout=5)

    def test_apply_skips_opted_out_updates_and_runs_other_updates(self) -> None:
        hook_path = SCRIPT.parents[1] / ".chezmoiscripts/run_onchange_after_80-apply_post.py"
        spec = importlib.util.spec_from_file_location("apply_post", hook_path)
        assert spec is not None
        assert spec.loader is not None
        hook = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hook)
        inventory = self.directory / ".chezmoidata"
        inventory.mkdir()
        has = self.directory / "has.toml"
        has.write_text("herdr = true\nother = true\n")
        entries = []
        for name, setting in (("herdr", "update_on_apply = false\n"), ("other", "")):
            marker = self.directory / name
            command = [
                sys.executable,
                "-c",
                f"from pathlib import Path; Path({str(marker)!r}).touch()",
            ]
            entries.append(f'name = "{name}"\n{setting}update = {json.dumps(command)}\n')
        (inventory / "tools.toml").write_text("".join(f"[[tools]]\n{entry}" for entry in entries))
        with (
            patch.object(hook, "HAS_FILE", has),
            patch.object(hook, "source_dir", return_value=self.directory),
        ):
            hook.update_cli_tools()
        assert not (self.directory / "herdr").exists()
        assert (self.directory / "other").exists()

    @unittest.skipUnless(os.name == "nt", "requires Windows DLL locking")
    def test_windows_loaded_dll_survives_bundle_replacement(self) -> None:
        executable = self.directory / "herdr.exe"
        executable.write_bytes(b"old executable")
        dll = self.directory / "conpty/conpty.dll"
        dll.parent.mkdir()
        shutil.copy2(Path(os.environ["SYSTEMROOT"]) / "System32/version.dll", dll)
        original = dll.read_bytes()
        if sys.platform == "win32":
            library = ctypes.WinDLL(str(dll))
            try:
                assert self.update(self.windows_archive(), "Windows", "AMD64") == 0
                assert (self.directory / "conpty_old/conpty.dll").read_bytes() == original
                assert dll.read_bytes() == b"new DLL"
            finally:
                ctypes.windll.kernel32.FreeLibrary(ctypes.c_void_p(library._handle))  # noqa: SLF001


if __name__ == "__main__":
    unittest.main()
