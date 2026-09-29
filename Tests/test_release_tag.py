"""Exercise release detection and tag publication against disposable Git repos."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "release_tag", Path(__file__).resolve().parents[1] / "scripts/release_tag.py"
)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        # Personal signing settings and hooks must not affect disposable fixtures.
        environment = patch.dict(
            os.environ, {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
        )
        environment.start()
        self.addCleanup(environment.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.original = Path.cwd()
        self.addCleanup(os.chdir, self.original)
        root = Path(self.temp.name)
        subprocess.run(
            ["git", "init", "--bare", "-q", str(root / "remote.git")], check=True
        )
        repo = root / "work"
        repo.mkdir()
        os.chdir(repo)
        release.git("init", "-q")
        release.git("config", "user.name", "Release test")
        release.git("config", "user.email", "release@example.invalid")
        release.git("remote", "add", "origin", str(root / "remote.git"))
        Path(release.PROJECT).parent.mkdir()
        self.before = self.commit("0.2.4")

    def commit(self, version, other=None):
        Path(release.PROJECT).write_text(
            f"MARKETING_VERSION = {version};\nMARKETING_VERSION = {other or version};\n"
        )
        release.git("add", release.PROJECT)
        release.git("commit", "-q", "--allow-empty", "-m", "Fixture")
        return release.git("rev-parse", "HEAD")

    def test_ordinary_commit_does_not_release_even_without_tag(self):
        self.assertIsNone(release.release_version(self.before, self.commit("0.2.4")))

    def test_numeric_version_increase(self):
        self.assertEqual(
            release.release_version(self.before, self.commit("0.2.10")), "0.2.10"
        )

    def test_invalid_or_inconsistent_versions_fail(self):
        for version, other in [("0.2.3", None), ("0.3.0", "0.2.4"), ("01.2.5", None)]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.release_version(self.before, self.commit(version, other))
        with self.assertRaises(ValueError):
            release.marketing_version("CURRENT_PROJECT_VERSION = 1;")

    def test_tag_targets_tested_commit_and_rerun_is_safe(self):
        tested = self.commit("0.2.5")
        self.commit("0.2.5")  # Main advances while CI is running.
        release.publish_tag("0.2.5", tested)
        self.assertEqual(release.remote_target("v0.2.5"), tested)
        self.assertEqual(release.git("cat-file", "-t", "v0.2.5"), "tag")
        release.publish_tag("0.2.5", tested)
        self.assertEqual(release.remote_target("v0.2.5"), tested)
        self.assertEqual(release.git("ls-remote", "--heads", "origin"), "")

    def test_remote_collision_preserves_original_tag(self):
        release.publish_tag("0.2.5", self.before)
        tested = self.commit("0.2.5")
        with self.assertRaises(ValueError):
            release.publish_tag("0.2.5", tested)
        self.assertEqual(release.remote_target("v0.2.5"), self.before)

    def test_local_collision_is_not_pushed(self):
        release.git("tag", "v0.2.5", self.before)
        with self.assertRaises(ValueError):
            release.publish_tag("0.2.5", self.commit("0.2.5"))
        self.assertIsNone(release.remote_target("v0.2.5"))

    def test_later_unchanged_commit_does_not_retry_a_failed_release(self):
        bumped = self.commit("0.2.5")
        self.assertIsNone(release.release_version(bumped, self.commit("0.2.5")))

    def test_read_only_cli_does_not_create_tag(self):
        tested = self.commit("0.3.0")
        subprocess.run(
            [
                sys.executable,
                str(Path(SPEC.origin)),
                "--before",
                self.before,
                "--commit",
                tested,
            ],
            check=True,
        )
        self.assertEqual(release.git("tag", "--list"), "")
        self.assertIsNone(release.remote_target("v0.3.0"))

    def run_publish(self, commit, output):
        subprocess.run(
            [
                sys.executable,
                str(Path(SPEC.origin)),
                "--before",
                self.before,
                "--commit",
                commit,
                "--publish",
            ],
            check=True,
            env={**os.environ, "GITHUB_OUTPUT": str(output)},
        )

    def test_publish_reports_tag_for_the_github_release(self):
        output = Path(self.temp.name) / "output"
        tested = self.commit("0.3.0")
        self.run_publish(tested, output)
        self.assertEqual(release.remote_target("v0.3.0"), tested)
        self.assertEqual(output.read_text(), "tag=v0.3.0\n")

    def test_unchanged_version_reports_no_tag(self):
        output = Path(self.temp.name) / "output"
        self.run_publish(self.commit("0.2.4"), output)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
