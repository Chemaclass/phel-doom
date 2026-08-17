<?php

declare(strict_types=1);

// Fail the build on a top-level definition in src/ that nothing references.
//
// The case this exists for: `secret-tex-offset` in render/main.phel. It was a
// real constant with a real docstring explaining the secret-wall cue (#469),
// and then the texture mips landed and the call site started computing the
// shift from the live mip size instead. The feature kept working, the def went
// dead, and its docstring kept confidently describing behaviour that was now
// derived somewhere else - the worst kind of stale, since it reads as current.
// Nothing catches this: the linter is per-form, the tests only exercise what is
// reachable, and `composer build` compiles dead code as happily as live code.
//
// A reference is any mention of the name as CODE anywhere under src/, tests/ or
// tools/ - bare (`foo`) or namespace-qualified (`r/foo`, `render/foo`). Comments,
// docstrings and `#_` forms are stripped first (shared with check-cycles.php via
// lib/phel-source.php), so a name that survives only in prose is still dead.
//
// Deliberately NOT flagged:
//   - test-only definitions. `default-grid`, the WAD lump readers and the demo
//     phase predicates are referenced only from tests/, which is a legitimate
//     shape (a fixture, or a parser whose only caller today is its own test).
//     Run with --report to list them for review.
//   - private `defn-`. Phel's own linter already flags an unused private.
//
// Usage: php tools/check-unused.php [--report]
// Exit 1 with the offending file:line when something is dead.

require_once __DIR__ . '/lib/phel-source.php';

const SCAN_DEFS_IN = 'src';
const SCAN_REFS_IN = ['src', 'tests', 'tools'];

/** @return list<string> */
function phelFiles(string $dir): array
{
    if (!is_dir($dir)) {
        return [];
    }
    $out = [];
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS));
    foreach ($it as $f) {
        if ($f->isFile() && $f->getExtension() === 'phel') {
            $out[] = $f->getPathname();
        }
    }
    sort($out);

    return $out;
}

/**
 * Top-level `(def ...)` / `(defn ...)` / `(defmacro ...)` / `(defstruct ...)`
 * names, keyed by name => [file, line, kind].
 *
 * Column 0 only: a nested def inside a `let` is not a namespace export, and a
 * `(def ...)` mentioned mid-line is prose or a macro body.
 *
 * @return array<string, array{string, int, string}>
 */
function topLevelDefs(string $dir): array
{
    $defs = [];
    foreach (phelFiles($dir) as $path) {
        $code = stripNonCode((string) file_get_contents($path));
        foreach (explode("\n", $code) as $i => $line) {
            if (!preg_match('/^\((def|defn|defmacro|defstruct)\s+([^\s()\[\]{}]+)/', $line, $m)) {
                continue;
            }
            [, $kind, $name] = $m;
            if (str_starts_with($name, '^')) {
                continue; // metadata sits before the name; next token is it
            }
            $defs[$name] = [$path, $i + 1, $kind];
        }
    }

    return $defs;
}

/**
 * Symbols appearing in one line of stripped source, as symbol => count.
 *
 * Splits on everything Phel cannot put inside a symbol, so `~foo` and `'foo`
 * yield `foo`. A qualified `r/foo` yields its tail too, since that is a real
 * reference to `foo`; a keyword `:foo` deliberately does not, because naming a
 * key is not using the definition that happens to share its name.
 *
 * @return array<string, int>
 */
function symbolsIn(string $line): array
{
    $out = [];
    foreach (preg_split('/[\s()\[\]{}"\'`~@^,;]+/u', $line, -1, PREG_SPLIT_NO_EMPTY) ?: [] as $tok) {
        $out[$tok] = ($out[$tok] ?? 0) + 1;
        $slash = strrpos($tok, '/');
        if ($slash !== false && $slash + 1 < strlen($tok)) {
            $tail = substr($tok, $slash + 1);
            $out[$tail] = ($out[$tail] ?? 0) + 1;
        }
    }

    return $out;
}

/**
 * Count references to each name, ignoring each name's own defining line.
 *
 * @param  array<string, array{string, int, string}>  $defs
 * @return array<string, list<string>>  name => files that reference it
 */
function referenceFiles(array $defs, array $dirs): array
{
    // Tokenise every file ONCE into symbol counts, rather than sweeping a
    // regex per definition per file: 762 definitions across ~190 files took
    // 10s that way, a quarter of the whole gate, for an answer that is one
    // pass over the same text.
    $counts = [];      // file => [symbol => count]
    $defLineHits = []; // file => [line => [symbol => count]]
    foreach ($dirs as $dir) {
        foreach (phelFiles($dir) as $path) {
            $lines = explode("\n", stripNonCode((string) file_get_contents($path)));
            $wanted = [];
            foreach ($defs as [$dp, $dl]) {
                if ($dp === $path) {
                    $wanted[$dl] = true;
                }
            }
            $counts[$path] = [];
            foreach ($lines as $i => $line) {
                $syms = symbolsIn($line);
                foreach ($syms as $s => $n) {
                    $counts[$path][$s] = ($counts[$path][$s] ?? 0) + $n;
                }
                if (isset($wanted[$i + 1])) {
                    $defLineHits[$path][$i + 1] = $syms;
                }
            }
        }
    }

    $found = [];
    foreach ($defs as $name => [$defPath, $defLine]) {
        $files = [];
        foreach ($counts as $path => $syms) {
            $hits = $syms[$name] ?? 0;
            if ($path === $defPath) {
                // Discount the definition itself, and ONLY it. Discounting the
                // whole line would drop the references that share it
                // (`(defn entry [x] (if (alive? x) ...))`), and discounting
                // every def line in the file would drop most references in a
                // module the size of render/main.phel.
                $hits -= min(1, $defLineHits[$path][$defLine][$name] ?? 0);
            }
            if ($hits > 0) {
                $files[] = $path;
            }
        }
        $found[$name] = $files;
    }

    return $found;
}

$report = in_array('--report', $argv, true);

$defs = topLevelDefs(SCAN_DEFS_IN);
if ($defs === []) {
    fwrite(STDERR, "check-unused: no definitions found under " . SCAN_DEFS_IN . "/ - wrong directory?\n");
    exit(2);
}

$refs = referenceFiles($defs, SCAN_REFS_IN);

$dead = [];
$testOnly = [];
foreach ($defs as $name => [$path, $line, $kind]) {
    $files = $refs[$name];
    if ($files === []) {
        $dead[$name] = [$path, $line, $kind];
    } elseif (array_filter($files, static fn (string $f): bool => !str_starts_with($f, 'tests/')) === []) {
        $testOnly[$name] = [$path, $line, $kind];
    }
}

if ($report) {
    printf("check-unused: %d definitions in %s/\n", count($defs), SCAN_DEFS_IN);
    printf("  referenced only from tests/ (%d, not an error):\n", count($testOnly));
    foreach ($testOnly as $name => [$path, $line, $kind]) {
        printf("    %s:%d  (%s) %s\n", $path, $line, $kind, $name);
    }
}

if ($dead !== []) {
    fwrite(STDERR, sprintf("check-unused: %d definition(s) referenced nowhere:\n", count($dead)));
    foreach ($dead as $name => [$path, $line, $kind]) {
        fwrite(STDERR, sprintf("  %s:%d  (%s) %s\n", $path, $line, $kind, $name));
    }
    fwrite(STDERR, "\nDelete it, or reference it. If it is a constant a refactor stopped\n");
    fwrite(STDERR, "using, its docstring is now describing behaviour that lives elsewhere.\n");
    exit(1);
}

printf("check-unused: %d definitions, none dead (%d test-only).\n", count($defs), count($testOnly));
exit(0);
