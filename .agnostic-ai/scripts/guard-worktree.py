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


def dangerous(command):
    for words in segments(command):
        while words:
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):
                words = words[1:]
            elif words[0] == "env":
                words = words[1:]
                while words and words[0].startswith("-"):
                    option = words.pop(0)
                    if option == "--":
                        break
                    if option in ("-u", "--unset") and words:
                        words.pop(0)
            elif words[0] in ("command", "exec"):
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
                if re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", word) and dangerous(words[index + 1]):
                    return True
        if executable != "git":
            continue
        args = words[1:]
        while args and args[0].startswith("-"):
            if args[0] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
                args = args[2:]
            else:
                args = args[1:]
        if not args:
            continue
        action, options = args[0], args[1:]
        if action == "stash" and not (options and options[0] in ("list", "show")):
            return True
        if action == "clean" and not {"-n", "--dry-run"} & set(options):
            return True
        if action == "restore":
            return True
        if action == "reset" and "--hard" in options:
            return True
        if action == "switch" and {"-f", "--force", "--discard-changes"} & set(options):
            return True
        if action == "checkout" and discards_checkout(options):
            return True
    return False


def discards_checkout(options):
    if {"-f", "--force"} & set(options):
        return True
    if "--" in options:
        return options.index("--") < len(options) - 1
    return any(option == "." or (not option.startswith("-") and os.path.exists(option)) for option in options)


def risky(command):
    try:
        return dangerous(command)
    except ValueError:
        return re.search(r"\bgit\b.*\b(stash|restore|clean|reset|checkout|switch)\b", command, re.S) is not None


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
