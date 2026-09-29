"""Validate the metadata script without changing the real repository or app."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/write_build_info.sh"


class BuildInfoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "source"
        self.repo.mkdir()
        self.output = self.root / "App.app/Contents/Resources/BuildInfo.json"
        self.environment = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.root),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }
        self.git("init", "-q")
        self.git("config", "user.name", "Build test")
        self.git("config", "user.email", "build@example.invalid")
        (self.repo / "source.txt").write_text("initial")
        self.git("add", ".")
        self.git("commit", "-qm", "initial")

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-C", str(self.repo), *args], env=self.environment, text=True
        ).strip()

    def generate(self, repo=None, **context):
        subprocess.run(
            ["/bin/sh", str(SCRIPT)],
            env={
                **self.environment,
                "SRCROOT": str(repo or self.repo),
                "SCRIPT_OUTPUT_FILE_0": str(self.output),
                **context,
            },
            check=True,
            capture_output=True,
        )
        return json.loads(self.output.read_text())

    def test_commit_change_refreshes_same_output(self):
        sha = self.git("rev-parse", "HEAD")
        self.assertEqual(self.generate(), {"commit": sha})
        (self.repo / "source.txt").write_text("modified")
        self.assertEqual(self.generate(), {"commit": sha})
        self.git("add", ".")
        self.git("commit", "-qm", "change")
        result = self.generate()
        self.assertNotEqual(result["commit"], sha)
        self.assertEqual(result["commit"], self.git("rev-parse", "HEAD"))

    def test_cloud_tag_uses_checkout_sha_and_ignores_cloud_changes(self):
        sha = self.git("rev-parse", "HEAD")
        self.git("tag", "v0.2.5")
        self.git("checkout", "--detach", "-q", "v0.2.5")
        (self.repo / "source.txt").write_text("Cloud build-number adjustment")
        result = self.generate(CI_XCODE_CLOUD="TRUE", CI_TAG="v0.2.5", CI_COMMIT=sha)
        self.assertEqual(result, {"commit": sha})
        with self.assertRaises(subprocess.CalledProcessError):
            self.generate(CI_XCODE_CLOUD="TRUE", CI_TAG="v0.2.5", CI_COMMIT="0" * 40)

    def test_linked_worktree_uses_its_own_head(self):
        worktree = self.root / "linked"
        self.git("worktree", "add", "--detach", "-q", str(worktree))
        self.assertEqual(
            self.generate(repo=worktree)["commit"], self.git("rev-parse", "HEAD")
        )

    def test_missing_git_metadata_fails(self):
        empty = self.root / "empty"
        empty.mkdir()
        with self.assertRaises(subprocess.CalledProcessError):
            self.generate(repo=empty)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
