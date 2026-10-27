#!/usr/bin/env python3
"""Focused behavior checks for the project agent hooks."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / ".agnostic-ai" / "scripts"


def run_hook(name, command="", path=None, cwd=ROOT, target=None):
    payload = {"tool_input": {"command": command}}
    if path is not None:
        payload["tool_input"]["file_path"] = str(path)
    runner = [sys.executable] if name.endswith(".py") else ["bash"]
    environment = os.environ.copy()
    if target:
        environment["AGNOSTIC_AI_TARGET"] = target
    else:
        environment.pop("AGNOSTIC_AI_TARGET", None)
    return subprocess.run(runner + [str(SCRIPTS / name)], cwd=cwd, input=json.dumps(payload), text=True, capture_output=True, env=environment, check=False)


class SilentGameTest(unittest.TestCase):
    def test_blocks_game_commands_without_silent_mode(self):
        for command in ("vendor/bin/phel run", "vendor/bin/phel test", "composer play", "composer dev", "composer test"):
            with self.subTest(command=command):
                result = run_hook("silent-game.py", command)
                self.assertEqual(2, result.returncode)
                self.assertIn("PHEL_DOOM_SILENT=1", result.stderr)

    def test_allows_game_commands_with_silent_mode(self):
        result = run_hook("silent-game.py", "PHEL_DOOM_SILENT=1 composer test")
        self.assertEqual(0, result.returncode, result.stderr)

    def test_allows_unrelated_commands(self):
        for command in ("composer ci", "composer --no-interaction ci", "env -u FOO PHEL_DOOM_SILENT=1 composer test"):
            with self.subTest(command=command):
                result = run_hook("silent-game.py", command)
                self.assertEqual(0, result.returncode, result.stderr)

    def test_blocks_commands_with_wrappers_and_options(self):
        for command in ("composer --no-interaction play", "composer run play", "composer run --no-interaction play", "composer run-script --timeout=0 play", "php vendor/bin/phel run", "php -d memory_limit=-1 vendor/bin/phel run", "env -u PHEL_DOOM_SILENT vendor/bin/phel run"):
            with self.subTest(command=command):
                result = run_hook("silent-game.py", command)
                self.assertEqual(2, result.returncode)


class GuardWorktreeTest(unittest.TestCase):
    def test_blocks_commands_that_discard_work(self):
        for command in ("git stash", "git checkout -- src/core/engine.phel", "git restore src/core/engine.phel", "git reset --hard", "git clean -fd"):
            with self.subTest(command=command):
                result = run_hook("guard-worktree.py", command)
                self.assertEqual(2, result.returncode)
                self.assertIn("approval", result.stderr.lower())

    def test_allows_non_destructive_git_command(self):
        for command in ("git status --short", "command -- git status", "env -u FOO git status"):
            with self.subTest(command=command):
                result = run_hook("guard-worktree.py", command)
                self.assertEqual(0, result.returncode, result.stderr)

    def test_blocks_wrapped_commands_that_discard_work(self):
        for command in ("command -- git clean", "env -u FOO git restore src/core/engine.phel"):
            with self.subTest(command=command):
                result = run_hook("guard-worktree.py", command)
                self.assertEqual(2, result.returncode)

    def test_claude_asks_for_approval_of_dangerous_commands(self):
        for command in ("git stash", "git checkout -- src/core/engine.phel", "git restore src/core/engine.phel", "git reset --hard", "git clean -fd"):
            with self.subTest(command=command):
                result = run_hook("guard-worktree.py", command, target="claude")
                self.assertEqual(0, result.returncode, result.stderr)
                reply = json.loads(result.stdout)
                output = reply["hookSpecificOutput"]
                self.assertEqual("PreToolUse", output["hookEventName"])
                self.assertEqual("ask", output["permissionDecision"])
                self.assertIn("discard", output["permissionDecisionReason"].lower())

    def test_claude_allows_safe_commands_without_an_approval_response(self):
        for command in ("git status --short", "git diff --check", "git log -1 --oneline"):
            with self.subTest(command=command):
                result = run_hook("guard-worktree.py", command, target="claude")
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("", result.stdout)


class CheckLayersTest(unittest.TestCase):
    def run_edit_hook(self, path):
        return subprocess.run(
            ["agnostic-ai", "hook", "run", "check-layers", "--edit", path, "--target", "claude,codex", "--expect", "allow"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_checks_a_changed_pure_layer_file(self):
        result = self.run_edit_hook("src/core/engine.phel")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Layering OK", result.stdout + result.stderr)

    def test_ignores_files_outside_pure_layers(self):
        result = self.run_edit_hook("src/io/input.phel")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotIn("Layering OK", result.stdout + result.stderr)

    def test_reports_a_pure_layer_violation(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            for directory in ("src/core", "src/glue", "src/demo", "src/io", "tools"):
                (project / directory).mkdir(parents=True, exist_ok=True)
            source = project / "src/core/bad.phel"
            contents = "(ns phel-doom.core.bad (:require phel-doom.io.sound))\n"
            source.write_text(contents)
            shutil.copy(ROOT / "tools/check-layers.sh", project / "tools/check-layers.sh")
            payload = {"hook_event_name": "PostToolUse", "tool_name": "Write", "tool_input": {"file_path": str(source), "content": contents}}
            environment = os.environ.copy()
            environment["CLAUDE_PROJECT_DIR"] = str(project)
            result = subprocess.run(["bash", str(SCRIPTS / "check-layers.sh")], cwd=project, input=json.dumps(payload), text=True, capture_output=True, env=environment, check=False)
            self.assertEqual(1, result.returncode)
            self.assertIn("LAYERING VIOLATION", result.stderr)


class WorktreeSetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.main = Path(self.temp.name) / "main"
        self.worktree = Path(self.temp.name) / "worktree"
        self.main.mkdir()
        self.git(self.main, "init", "-q")
        self.git(self.main, "config", "user.email", "test@example.test")
        self.git(self.main, "config", "user.name", "Test")
        (self.main / ".githooks").mkdir()
        shutil.copy(ROOT / ".githooks/post-checkout", self.main / ".githooks/post-checkout")
        (self.main / "composer.lock").write_text("{}\n")
        (self.main / "tracked").write_text("tracked\n")
        self.git(self.main, "add", ".")
        self.git(self.main, "commit", "-qm", "initial")
        (self.main / "vendor").mkdir()
        (self.main / ".phel").mkdir()
        self.git(self.main, "worktree", "add", "-qb", "feature", str(self.worktree))
        (self.worktree / "composer.lock").unlink()

    def git(self, cwd, *args):
        subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)

    def test_links_dependencies_in_a_linked_worktree(self):
        result = subprocess.run(["bash", str(SCRIPTS / "worktree-setup.sh")], cwd=self.worktree, text=True, capture_output=True, check=False)
        self.assertEqual(0, result.returncode, result.stderr)
        for name in ("vendor", "composer.lock", ".phel"):
            path = self.worktree / name
            self.assertTrue(path.is_symlink(), name)
            self.assertEqual((self.main / name).resolve(), path.resolve())

    def test_does_nothing_in_the_main_checkout(self):
        vendor = self.main / "vendor"
        self.assertFalse(vendor.is_symlink())
        result = subprocess.run(["bash", str(SCRIPTS / "worktree-setup.sh")], cwd=self.main, text=True, capture_output=True, check=False)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(vendor.is_symlink())

    def test_post_checkout_syncs_only_new_worktrees_without_vendor(self):
        bin_dir = Path(self.temp.name) / "bin"
        bin_dir.mkdir()
        log = Path(self.temp.name) / "agnostic-ai.log"
        command = bin_dir / "agnostic-ai"
        command.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$AGENT_HOOK_LOG\"\nif [ \"$1\" = sync ]; then mkdir -p .codex; : > .codex/hooks.json; fi\n")
        command.chmod(0o755)
        environment = os.environ.copy()
        environment["AGENT_HOOK_LOG"] = str(log)
        environment["PATH"] = f"{bin_dir}:{environment['PATH']}"
        hook = self.worktree / ".githooks/post-checkout"
        result = subprocess.run(["bash", str(hook), "old", "new", "1"], cwd=self.worktree, env=environment, text=True, capture_output=True, check=False)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue((self.worktree / ".codex/hooks.json").is_file())
        self.assertEqual("sync\n", log.read_text())

        log.unlink()
        (self.worktree / "vendor").mkdir()
        for checkout in (self.main, self.worktree):
            result = subprocess.run(["bash", str(checkout / ".githooks/post-checkout"), "old", "new", "1"], cwd=checkout, env=environment, text=True, capture_output=True, check=False)
            self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
