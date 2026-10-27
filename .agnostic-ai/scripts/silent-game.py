#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / ".agnostic-ai" / "scripts"))
from shell_words import segments, shell_scripts, unwrap, without_options  # noqa: E402


MAKE_VALUE_OPTIONS = ("-C", "--directory", "-f", "--file", "--makefile", "-I", "--include-dir", "-o", "-W")


def silenced(silent, changes):
    for change in changes:
        if change[0] == "clear":
            silent = False
        elif change[1] == "PHEL_DOOM_SILENT":
            silent = change[0] == "set" and change[2] == "1"
    return silent


def unsafe(command, silent):
    for words in segments(command):
        if words[0] == "export":
            silent = silenced(silent, [("set", *word.split("=", 1)) for word in words[1:] if "=" in word])
            continue
        words, changes = unwrap(words)
        current = silenced(silent, changes)
        if not words:
            continue
        if any(unsafe(script, current) for script in shell_scripts(words)):
            return True
        if current:
            continue
        executable = os.path.basename(words[0])
        if executable == "php" and len(words) > 1:
            words = without_options(words[1:], ("-d", "-c", "-z"))
            if not words:
                continue
            if re.search(r"(?:^|/)out/main\.php$", words[0]):
                return True
            executable = os.path.basename(words[0])
        if executable == "phel":
            args = without_options(words[1:])
            if args and args[0] in ("run", "test", "bench"):
                return True
        if executable == "composer":
            value_options = ("-d", "--working-dir", "--format", "--timeout")
            args = without_options(words[1:], value_options)
            if args and args[0] in ("run", "run-script"):
                args = without_options(args[1:], value_options)
            if args and args[0] in ("play", "dev"):
                return True
        if executable == "make":
            args = words[1:]
            if "PHEL_DOOM_SILENT=1" in args:
                continue
            targets = []
            while args:
                arg = args.pop(0)
                if arg in MAKE_VALUE_OPTIONS and args:
                    args.pop(0)
                elif not arg.startswith("-") and "=" not in arg:
                    targets.append(arg)
            if {"play", "p", "dev", "d"} & set(targets):
                return True
    return False


def risky(command, silent):
    try:
        return unsafe(command, silent)
    except ValueError:
        return not silent and re.search(r"\b(phel|composer|make|out/main\.php)\b", command) is not None and "PHEL_DOOM_SILENT=1" not in command


def main():
    try:
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command") or payload.get("command") or ""
    except (ValueError, AttributeError):
        command = None
    if not isinstance(command, str):
        print("Could not inspect the command for silent mode.", file=sys.stderr)
        return 2
    if risky(command, os.environ.get("PHEL_DOOM_SILENT") == "1"):
        print("Run this command with PHEL_DOOM_SILENT=1 to silence the game.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
