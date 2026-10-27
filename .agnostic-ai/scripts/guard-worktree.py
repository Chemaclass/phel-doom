#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / ".agnostic-ai" / "scripts"))
from shell_words import segments, shell_scripts, unwrap  # noqa: E402

GIT_VALUE_OPTIONS = ("-c", "--git-dir", "--work-tree", "--namespace")
CHECKOUT_VALUE_OPTIONS = ("-b", "-B", "--orphan", "--conflict", "--pathspec-from-file")


def has_flag(options, short, *long):
    return any(option in long or re.fullmatch(rf"-[a-zA-Z]*{short}[a-zA-Z]*", option) for option in options)


def dangerous(command, cwd="."):
    for words in segments(command):
        words, _ = unwrap(words)
        if not words:
            continue
        if words[0] == "cd" and len(words) > 1:
            cwd = os.path.join(cwd, words[1])
            continue
        if any(dangerous(script, cwd) for script in shell_scripts(words)):
            return True
        if os.path.basename(words[0]) != "git":
            continue
        args, directory = words[1:], cwd
        while args and args[0].startswith("-"):
            option = args.pop(0)
            if option == "-C" and args:
                directory = os.path.join(directory, args.pop(0))
            elif option in GIT_VALUE_OPTIONS and args:
                args.pop(0)
        if args and discards(args[0], args[1:], directory):
            return True
    return False


def discards(action, options, directory):
    if action == "stash":
        return not (options and options[0] in ("list", "show"))
    if action == "clean":
        return not has_flag(options, "n", "--dry-run")
    if action == "restore":
        return not has_flag(options, "S", "--staged") or has_flag(options, "W", "--worktree")
    if action == "rm":
        return has_flag(options, "f", "--force")
    if action == "reset":
        return "--hard" in options
    if action == "switch":
        return has_flag(options, "f", "--force", "--discard-changes")
    if action == "checkout":
        return discards_checkout(options, directory)
    return False


def discards_checkout(options, directory):
    if has_flag(options, "f", "--force"):
        return True
    if "--" in options:
        return options.index("--") < len(options) - 1
    targets = []
    options = list(options)
    while options:
        option = options.pop(0)
        if option in CHECKOUT_VALUE_OPTIONS and options:
            options.pop(0)
        elif not option.startswith("-"):
            targets.append(option)
    if len(targets) > 1:
        return True
    return any(target == "." or os.path.exists(os.path.join(directory, target)) for target in targets)


def risky(command):
    try:
        return dangerous(command)
    except ValueError:
        return re.search(r"\bgit\b.*\b(stash|restore|clean|reset|checkout|switch|rm)\b", command, re.S) is not None


def main():
    try:
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command") or payload.get("command") or ""
    except (ValueError, AttributeError):
        command = None
    if not isinstance(command, str):
        print("Could not inspect the command for working tree changes.", file=sys.stderr)
        return 2
    if not risky(command):
        return 0
    if os.environ.get("AGNOSTIC_AI_TARGET") == "claude":
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "This command can discard working changes and needs approval."}}))
        return 0
    print("Ask the user for approval before running this command, which can discard working changes.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
