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
        if action in ("stash", "restore", "clean"):
            return True
        if action == "reset" and "--hard" in options:
            return True
        if action == "checkout" and "--" in options and options.index("--") < len(options) - 1:
            return True
    return False


def main():
    try:
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command") or payload.get("command") or ""
        if dangerous(command):
            if os.environ.get("AGNOSTIC_AI_TARGET") == "claude":
                print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "This command can discard working changes and needs approval."}}))
                return 0
            print("Ask the user for approval before running this command, which can discard working changes.", file=sys.stderr)
            return 2
    except (ValueError, TypeError, AttributeError):
        print("Could not inspect the command for working tree changes.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
