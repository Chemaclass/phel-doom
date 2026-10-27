#!/usr/bin/env python3
import json
import os
import re
import shlex
import sys


def segments(command):
    lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = ""
    segment = []
    for word in lexer:
        if all(char in ";&|()" for char in word):
            if segment:
                yield segment
                segment = []
        else:
            segment.append(word)
    if segment:
        yield segment


def without_options(args, value_options):
    while args and args[0].startswith("-"):
        option = args.pop(0)
        if option == "--":
            break
        if option in value_options and args:
            args.pop(0)
    return args


def unsafe(command, silent):
    for words in segments(command):
        current = silent
        while words:
            word = words[0]
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", word):
                name, value = word.split("=", 1)
                if name == "PHEL_DOOM_SILENT":
                    current = value == "1"
                words = words[1:]
            elif word == "env":
                words = words[1:]
                while words and words[0].startswith("-"):
                    option = words.pop(0)
                    if option == "--":
                        break
                    if option in ("-i", "--ignore-environment"):
                        current = False
                    elif option in ("-u", "--unset") and words:
                        name = words.pop(0)
                        if name == "PHEL_DOOM_SILENT":
                            current = False
                    elif option == "--unset=PHEL_DOOM_SILENT":
                        current = False
            elif word in ("command", "exec"):
                words = words[1:]
                if words and words[0] == "--":
                    words = words[1:]
            else:
                break
        if not words:
            continue
        executable = os.path.basename(words[0])
        if executable in ("sh", "bash", "zsh", "dash"):
            for index, word in enumerate(words[1:-1], 1):
                if re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", word) and unsafe(words[index + 1], current):
                    return True
        if current:
            continue
        if executable == "php" and len(words) > 1:
            words = without_options(words[1:], ("-d", "-c", "-z"))
            if not words:
                continue
            if re.search(r"(?:^|/)out/main\.php$", words[0]):
                return True
            executable = os.path.basename(words[0])
        if executable == "phel" and len(words) > 1 and words[1] in ("run", "test"):
            return True
        if executable == "composer":
            value_options = ("-d", "--working-dir", "--format", "--timeout")
            args = without_options(words[1:], value_options)
            if args and args[0] in ("run", "run-script"):
                args = without_options(args[1:], value_options)
            if args and args[0] in ("play", "dev"):
                return True
    return False


def risky(command, silent):
    try:
        return unsafe(command, silent)
    except ValueError:
        return not silent and re.search(r"\b(phel|composer|out/main\.php)\b", command) is not None and "PHEL_DOOM_SILENT=1" not in command


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
