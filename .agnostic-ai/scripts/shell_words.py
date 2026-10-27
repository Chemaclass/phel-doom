import re
import shlex

ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*")
SHELLS = ("sh", "bash", "zsh", "dash")
KEYWORDS = ("if", "then", "else", "elif", "fi", "while", "until", "do", "done", "!", "{", "}")
VALUE_OPTIONS = {
    "env": ("-u", "--unset", "-C", "--chdir", "-S", "--split-string"),
    "nice": ("-n", "--adjustment"),
    "timeout": ("-s", "--signal", "-k", "--kill-after"),
    "sudo": ("-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "--close-from", "-D", "--chdir", "-r", "--role", "-t", "--type", "-T", "--command-timeout"),
    "xargs": ("-I", "-L", "-n", "-P", "-d", "-E", "-s", "-a", "--arg-file", "--delimiter", "--max-args", "--max-procs", "--max-lines", "--max-chars", "--eof", "--replace"),
}


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


def without_options(args, value_options=()):
    while args and args[0].startswith("-"):
        option = args.pop(0)
        if option == "--":
            break
        if option in value_options and args:
            args.pop(0)
    return args


def unwrap(words):
    words = list(words)
    changes = []
    while words:
        word = words[0]
        if word in KEYWORDS:
            words.pop(0)
            continue
        if ASSIGNMENT.fullmatch(word):
            name, value = word.split("=", 1)
            changes.append(("set", name, value))
            words.pop(0)
            continue
        wrapper = word.rsplit("/", 1)[-1]
        if wrapper == "env":
            words.pop(0)
            while words and words[0].startswith("-"):
                option = words.pop(0)
                if option == "--":
                    break
                if option in ("-i", "--ignore-environment", "-"):
                    changes.append(("clear",))
                elif option in ("-u", "--unset") and words:
                    changes.append(("unset", words.pop(0)))
                elif option.startswith("--unset="):
                    changes.append(("unset", option.split("=", 1)[1]))
                elif option in VALUE_OPTIONS["env"] and words:
                    value = words.pop(0)
                    if option in ("-S", "--split-string"):
                        words = shlex.split(value) + words
        elif wrapper in ("command", "exec", "time", "nohup", "nice", "xargs"):
            words = without_options(words[1:], VALUE_OPTIONS.get(wrapper, ()))
        elif wrapper == "timeout":
            words = without_options(words[1:], VALUE_OPTIONS["timeout"])[1:]
        elif wrapper == "sudo":
            changes.append(("clear",))
            words = without_options(words[1:], VALUE_OPTIONS["sudo"])
        else:
            break
    return words, changes


def shell_scripts(words):
    if not words or words[0].rsplit("/", 1)[-1] not in SHELLS:
        return
    for index, word in enumerate(words[1:-1], 1):
        if re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", word):
            yield words[index + 1]
