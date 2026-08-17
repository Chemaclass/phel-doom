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
// Private `defn-` / `def-` are INCLUDED. The header used to say the linter
// already flagged those; it does not - `composer lint` passes clean on both an
// unused `def-` and an unused `defn-`, checked directly. The gap was not
// theoretical: #516 orphaned a private `bfs-steps` and neither this guard nor
// the linter said a word.
//
// Known limit: references are resolved by NAME, not by namespace. Two files
// defining `reset!` share one verdict, so one of them can be dead while the
// other keeps the pair green. Namespace-accurate resolution means following
// every `:as` / `:refer` in every ns form, which is a different tool; the
// facade re-export case that actually occurs here is handled explicitly.
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
 * definitions, as name => list of [file, line, kind].
 *
 * Column 0 only: a nested def inside a `let` is not a namespace export, and a
 * `(def ...)` mentioned mid-line is prose or a macro body.
 *
 * Metadata is skipped rather than the definition: `(defn ^:pure foo ...)` is
 * still a definition of `foo`, and ~30 of them carry the inliner's `^:pure`
 * tag. Reading the meta token as the name and giving up hid every one of them
 * from the guard - and the count it printed.
 *
 * A name can appear more than once: `render.phel` re-exports the sub-namespace
 * API (`(def render! render/render!)`), so the facade and the implementation
 * both define it. Keeping only the last would let the two mask each other
 * forever, since each one's defining line reads as a reference to the other.
 *
 * @return array<string, list<array{string, int, string}>>
 */
function topLevelDefs(string $dir): array
{
    $defs = [];
    foreach (phelFiles($dir) as $path) {
        $code = stripNonCode((string) file_get_contents($path));
        foreach (explode("\n", $code) as $i => $line) {
            if (!preg_match('/^\((def-|defn-|def|defn|defmacro|defstruct)\s+(?:\^\S+\s+)*([^\s()\[\]{}]+)/', $line, $m)) {
                continue;
            }
            [, $kind, $name] = $m;
            $defs[$name][] = [$path, $i + 1, $kind];
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
 * Is this def line a bare re-export of the same name from another namespace,
 * as `src/io/render.phel` does for the whole sub-namespace API?
 */
function isReexport(string $line, string $name): bool
{
    $q = preg_quote($name, '/');

    return preg_match('/^\(def\s+(?:\^\S+\s+)*' . $q . '\s+[^\s()\[\]{}]+\/' . $q . '\s*\)\s*$/u', $line) === 1;
}

/**
 * Count references to each name, ignoring the lines that define it.
 *
 * @param  array<string, list<array{string, int, string}>>  $defs
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
    $defLineText = []; // file => [line => source line]
    foreach ($dirs as $dir) {
        foreach (phelFiles($dir) as $path) {
            $lines = explode("\n", stripNonCode((string) file_get_contents($path)));
            $wanted = [];
            foreach ($defs as $sites) {
                foreach ($sites as [$dp, $dl]) {
                    if ($dp === $path) {
                        $wanted[$dl] = true;
                    }
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
                    $defLineText[$path][$i + 1] = $line;
                }
            }
        }
    }

    $found = [];
    foreach ($defs as $name => $sites) {
        // `(defstruct point [x y])` also defines `point?`, so a struct whose
        // only use is its predicate is live. Fields are read with keywords, so
        // there are no generated accessor names to track.
        $aliases = [];
        foreach ($sites as [, , $kind]) {
            if ($kind === 'defstruct') {
                $aliases[] = $name . '?';
            }
        }
        $files = [];
        foreach ($counts as $path => $syms) {
            $hits = $syms[$name] ?? 0;
            foreach ($aliases as $alias) {
                $hits += $syms[$alias] ?? 0;
            }
            foreach ($sites as [$defPath, $defLine]) {
                if ($defPath !== $path) {
                    continue;
                }
                // Discount each definition itself, and ONLY it. Discounting the
                // whole line would drop the references that share it
                // (`(defn entry [x] (if (alive? x) ...))`), and discounting
                // every def line in the file would drop most references in a
                // module the size of render/main.phel.
                //
                // A facade re-export (`(def render! render/render!)`) is the
                // exception: it mentions the name twice, and the qualified half
                // is not a use of the API - it IS the API being forwarded. Left
                // counted, a re-exported name could never be flagged, because
                // each of its two definitions read as a use of the other.
                $onLine = $defLineHits[$path][$defLine][$name] ?? 0;
                $line = $defLineText[$path][$defLine] ?? '';
                $hits -= isReexport($line, $name) ? $onLine : min(1, $onLine);
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
foreach ($defs as $name => $sites) {
    $files = $refs[$name];
    if ($files === []) {
        $dead[$name] = $sites;
    } elseif (array_filter($files, static fn (string $f): bool => !str_starts_with($f, 'tests/')) === []) {
        $testOnly[$name] = $sites;
    }
}

$total = array_sum(array_map(count(...), $defs));

/** @param array<string, list<array{string, int, string}>> $group */
function listSites(array $group, string $indent): string
{
    $out = '';
    foreach ($group as $name => $sites) {
        foreach ($sites as [$path, $line, $kind]) {
            $out .= sprintf("%s%s:%d  (%s) %s\n", $indent, $path, $line, $kind, $name);
        }
    }

    return $out;
}

if ($report) {
    printf("check-unused: %d definitions in %s/\n", $total, SCAN_DEFS_IN);
    printf("  referenced only from tests/ (%d, not an error):\n", count($testOnly));
    print listSites($testOnly, '    ');
}

if ($dead !== []) {
    fwrite(STDERR, sprintf("check-unused: %d name(s) referenced nowhere:\n", count($dead)));
    fwrite(STDERR, listSites($dead, '  '));
    fwrite(STDERR, "\nDelete it, or reference it. If it is a constant a refactor stopped\n");
    fwrite(STDERR, "using, its docstring is now describing behaviour that lives elsewhere.\n");
    fwrite(STDERR, "A name listed twice is defined twice (a facade re-export); both\n");
    fwrite(STDERR, "sites are dead, since neither counts as a use of the other.\n");
    exit(1);
}

printf("check-unused: %d definitions, none dead (%d test-only).\n", $total, count($testOnly));
exit(0);
