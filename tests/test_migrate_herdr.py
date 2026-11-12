"""Offline migration fixtures: never contact or stop a real Herdr server."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("migration", Path(__file__).resolve().parents[1] / "migrate-herdr.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "dotfiles"
        self.source = self.home / ".config/herdr"
        self.target = self.repo / "herdr/.config/herdr"
        self.source.mkdir(parents=True)
        self.target.mkdir(parents=True)
        (self.target / "config.base.toml").write_text("tracked config\n")
        (self.source / "config.base.toml").symlink_to(self.target / "config.base.toml")
        self.agent = self.home / ".pi/conversation.jsonl"
        self.agent.parent.mkdir()
        self.agent.write_text('saved conversation\n')
        self.session = json.dumps({"workspaces": [{"agent_session": {
            "kind": "path", "value": str(self.agent)}}]})
        (self.source / "session.json").write_text(self.session)
        (self.source / "config.toml").write_text("local generated config\n")
        (self.source / "config.toml").chmod(0o600)

    def entries(self):
        return [(self.source, self.target, migration.plan(self.source, self.target))]

    def test_preserves_layout_agent_local_data_and_permissions(self):
        migration.apply(self.home, self.repo, self.entries(), migration.agent_paths(self.source))
        self.assertTrue(self.source.is_symlink())
        self.assertEqual(self.source.resolve(), self.target.resolve())
        self.assertEqual((self.source / "session.json").read_text(), self.session)
        self.assertEqual((self.target / "config.toml").stat().st_mode & 0o777, 0o600)
        manifest_path = next((self.home / ".local/state/dotfiles-backups").glob("*/manifest.json"))
        manifest = json.loads(manifest_path.read_text())
        original = Path(manifest["directories"][0]["backup"])
        self.assertEqual((original / "session.json").read_text(), self.session)
        self.assertEqual(Path(manifest["agent_backups"][0]["backup"]).read_bytes(), self.agent.read_bytes())
        # A second run is a no-op, not a second destructive migration.
        self.assertEqual(migration.plan(self.source, self.target), [])
        # Rollback restores relative/absolute original links at their old location.
        self.source.unlink()
        original.rename(self.source)
        self.assertEqual((self.source / "config.base.toml").read_text(), "tracked config\n")

    def test_relative_external_link_keeps_its_original_referent(self):
        external = self.home / "external/data"
        external.parent.mkdir()
        external.write_text("external data\n")
        link = self.source / "external-link"
        link.symlink_to(os.path.relpath(external, link.parent))
        original_text = os.readlink(link)
        migration.apply(self.home, self.repo, self.entries(), [])
        moved = self.target / link.name
        self.assertEqual(moved.resolve(strict=True), external.resolve())
        self.assertNotEqual(os.readlink(moved), original_text)
        self.assertEqual(moved.read_text(), "external data\n")

    def test_relative_internal_file_and_directory_links_follow_migrated_state(self):
        state = self.source / "state"
        state.mkdir()
        (state / "data").write_text("local state\n")
        (self.source / "file-link").symlink_to("state/data")
        (self.source / "directory-link").symlink_to("state", target_is_directory=True)
        migration.apply(self.home, self.repo, self.entries(), [])
        self.assertEqual((self.target / "file-link").resolve(strict=True),
                         (self.target / "state/data").resolve())
        self.assertEqual((self.target / "directory-link").resolve(strict=True),
                         (self.target / "state").resolve())
        # Editing migrated state must be visible through both links, not backup data.
        (self.target / "state/data").write_text("new state\n")
        self.assertEqual((self.target / "file-link").read_text(), "new state\n")
        self.assertEqual((self.target / "directory-link/data").read_text(), "new state\n")

    def test_broken_relative_link_aborts_before_writes(self):
        (self.source / "broken").symlink_to("missing")
        with self.assertRaisesRegex(RuntimeError, "Broken or cyclic symlink"):
            self.entries()
        self.assertFalse(self.source.is_symlink())
        self.assertFalse((self.target / "session.json").exists())

    def test_conflicting_files_abort_before_changes(self):
        (self.target / "config.toml").write_text("different\n")
        with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
            self.entries()
        self.assertFalse(self.source.is_symlink())

    def test_missing_agent_reference_aborts(self):
        self.agent.unlink()
        with self.assertRaisesRegex(RuntimeError, "Missing agent session"):
            migration.agent_paths(self.source)

    def test_stale_socket_is_not_copied(self):
        sock = socket.socket(socket.AF_UNIX)
        self.addCleanup(sock.close)
        # macOS limits Unix socket path lengths; the temp fixture may be deep.
        with tempfile.TemporaryDirectory(dir="/tmp") as short:
            path = Path(short) / "herdr.sock"
            sock.bind(str(path))
            self.assertEqual(migration.plan(Path(short), self.target), [])

    def test_copy_failure_restores_original_and_removes_partial_copies(self):
        real_copy = migration.shutil.copy2
        def fail_on_config(src, dst):
            if Path(src).name == "config.toml":
                Path(dst).write_text("partial")
                raise OSError("fixture copy failure")
            return real_copy(src, dst)
        with patch.object(migration.shutil, "copy2", side_effect=fail_on_config):
            with self.assertRaisesRegex(OSError, "fixture copy failure"):
                migration.apply(self.home, self.repo, self.entries(), [])
        self.assertFalse(self.source.is_symlink())
        self.assertEqual((self.source / "session.json").read_text(), self.session)
        self.assertFalse((self.target / "config.toml").exists())
        self.assertFalse((self.target / "session.json").exists())

    def test_link_failure_restores_moved_directory(self):
        real_symlink = Path.symlink_to
        def fail_source_link(path, *args, **kwargs):
            if path == self.source:
                raise OSError("fixture symlink failure")
            return real_symlink(path, *args, **kwargs)
        with patch.object(Path, "symlink_to", fail_source_link):
            with self.assertRaisesRegex(OSError, "fixture symlink failure"):
                migration.apply(self.home, self.repo, self.entries(), [])
        self.assertFalse(self.source.is_symlink())
        self.assertEqual((self.source / "session.json").read_text(), self.session)
        self.assertFalse((self.target / "session.json").exists())

    def test_apply_refuses_running_server_before_migration(self):
        with patch.object(migration.sys, "argv", ["migrate-herdr.py", "--apply"]), \
             patch.object(migration, "sessions", return_value=[{"name": "default", "running": True}]), \
             patch.object(migration, "apply") as apply:
            with self.assertRaisesRegex(RuntimeError, "ALL listed sessions"):
                migration.main()
            apply.assert_not_called()

    def test_wrong_directory_link_is_rejected(self):
        other = self.home / "wrong"
        other.symlink_to(self.home)
        with self.assertRaisesRegex(RuntimeError, "Unexpected directory symlink"):
            migration.plan(other, self.target)


if __name__ == "__main__":
    unittest.main()
