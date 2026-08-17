<?php

declare(strict_types=1);

// Fail the build on a doc that points at something which is not there.
//
// `docs/` is part of this codebase - a stale doc is a blocking issue here, not
// a tidy-up - but the parts of a doc that rot silently are the mechanical ones.
// Nobody clicks every cross-reference on a rename. When this guard was written
// it found `[Pixel-doubling](#pixel-doubling)` in rendering.md (the section had
// been retitled "Pixel-doubled mode"), a link into input.md aimed at a heading
// that no longer existed, and two file paths written with hyphens and no
// extension (`src/io/sound-data`) that nothing on disk matches - so a reader
// who greps for what the doc names finds nothing.
//
// Four checks, all of them yes-or-no:
//   1. a relative markdown link resolves to a file that exists
//   2. a `#fragment` resolves to a heading in the target file
//   3. a backticked repo path (`src/...`, `tools/...`) exists
//   4. a backticked `composer <script>` is a real script or a composer builtin
//
// Prose is NOT checked. An earlier cut tried to verify that every backticked
// kebab-case name in the docs was a real definition and produced 97 hits,
// nearly all of them `let` bindings, bench row names and map keys named in
// perfectly correct prose. A guard that noisy gets ignored, and an ignored
// guard is worse than none.
//
// Usage: php tools/check-docs.php
// Exit 1, with file:line for every claim that does not hold.

const DOC_GLOBS = ['docs/*.md', 'docs/**/*.md', 'README.md', 'tools/README.md', 'CHANGELOG.md'];

// Paths inside these are HISTORY. An ADR describes a decision as it was, a
// changelog entry describes a release as it shipped; both legitimately name
// files that a later commit removed, and rewriting them to keep a guard happy
// would be falsifying the record. Their links and anchors are still checked.
const NO_PATH_CHECK = ['docs/adr/', 'CHANGELOG.md'];

// Composer's own commands. `composer install` is not in the scripts block and
// never will be.
const COMPOSER_BUILTINS = [
    'install', 'update', 'require', 'remove', 'dump-autoload', 'validate',
    'outdated', 'show', 'why', 'why-not', 'audit', 'create-project', 'run-script',
    'exec', 'clear-cache', 'self-update', 'diagnose', 'licenses', 'init',
];

/** @return list<string> */
function docFiles(): array
{
    $out = [];
    foreach (DOC_GLOBS as $glob) {
        foreach (glob($glob, GLOB_BRACE) ?: [] as $f) {
            $out[$f] = true;
        }
    }
    // glob's `**` is not recursive in PHP; walk docs/ for nested files.
    if (is_dir('docs')) {
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator('docs', FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if ($f->isFile() && $f->getExtension() === 'md') {
                $out[$f->getPathname()] = true;
            }
        }
    }
    $files = array_keys($out);
    sort($files);

    return $files;
}

/**
 * GitHub's heading slugs: lowercase, punctuation dropped, spaces to hyphens,
 * and a `-1`, `-2` suffix for each repeat of an already-used slug.
 *
 * @return array<string, true>
 */
function headingAnchors(string $path): array
{
    $seen = [];
    $anchors = [];
    $inFence = false;
    foreach (file($path, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        if (preg_match('/^\s*(```|~~~)/', $line) === 1) {
            $inFence = !$inFence;
            continue;
        }
        // A `# comment` inside a fenced block is shell, not a heading.
        if ($inFence || !preg_match('/^#{1,6}\s+(.+?)\s*$/', $line, $m)) {
            continue;
        }
        $slug = strtolower($m[1]);
        $slug = preg_replace('/[^\p{L}\p{N}\s_-]+/u', '', $slug) ?? '';
        $slug = str_replace(' ', '-', trim($slug));
        $n = $seen[$slug] ?? 0;
        $seen[$slug] = $n + 1;
        $anchors[$n === 0 ? $slug : $slug . '-' . $n] = true;
    }

    return $anchors;
}

/** Lines of a file with fenced code blocks blanked, keeping line numbers. */
function withoutFences(string $path): array
{
    $lines = file($path, FILE_IGNORE_NEW_LINES) ?: [];
    $inFence = false;
    foreach ($lines as $i => $line) {
        if (preg_match('/^\s*(```|~~~)/', $line) === 1) {
            $inFence = !$inFence;
            $lines[$i] = '';
            continue;
        }
        if ($inFence) {
            $lines[$i] = '';
        }
    }

    return $lines;
}

$docs = docFiles();
if ($docs === []) {
    fwrite(STDERR, "check-docs: no markdown found - wrong directory?\n");
    exit(2);
}

$composerScripts = [];
if (is_file('composer.json')) {
    $json = json_decode((string) file_get_contents('composer.json'), true);
    $composerScripts = array_keys($json['scripts'] ?? []);
}

$anchorCache = [];
$problems = [];

foreach ($docs as $doc) {
    $dir = dirname($doc);
    $skipPaths = false;
    foreach (NO_PATH_CHECK as $prefix) {
        if (str_starts_with($doc, $prefix)) {
            $skipPaths = true;
        }
    }

    // Links and fragments: checked in the raw text, since a link inside a
    // fenced example is still a link a reader can click.
    foreach (file($doc, FILE_IGNORE_NEW_LINES) ?: [] as $i => $line) {
        foreach (preg_match_all('/\[[^\]]*\]\(([^)\s]+)\)/', $line, $m) ? $m[1] : [] as $target) {
            if (preg_match('#^(https?:|mailto:|tel:)#', $target) === 1) {
                continue;
            }
            $fragment = null;
            $file = $target;
            if (str_contains($target, '#')) {
                [$file, $fragment] = explode('#', $target, 2);
            }
            $path = $file === '' ? $doc : realpathish($dir . '/' . $file);
            if ($file !== '' && !is_file($path)) {
                $problems[] = sprintf('%s:%d  link to a file that does not exist: %s', $doc, $i + 1, $target);
                continue;
            }
            if ($fragment === null || $fragment === '' || !str_ends_with($path, '.md')) {
                continue;
            }
            $anchorCache[$path] ??= headingAnchors($path);
            if (!isset($anchorCache[$path][strtolower(rawurldecode($fragment))])) {
                $problems[] = sprintf('%s:%d  link to a heading that does not exist: %s', $doc, $i + 1, $target);
            }
        }
    }

    // Backticked claims: skipped inside fenced blocks, which are transcripts
    // and command examples rather than statements about the tree.
    foreach (withoutFences($doc) as $i => $line) {
        foreach (preg_match_all('/`([^`]+)`/', $line, $m) ? $m[1] : [] as $tok) {
            $tok = trim($tok);
            if (preg_match('/^composer ([a-z0-9:-]+)$/', $tok, $cm) === 1) {
                if (!in_array($cm[1], $composerScripts, true) && !in_array($cm[1], COMPOSER_BUILTINS, true)) {
                    $problems[] = sprintf('%s:%d  no such composer script: %s', $doc, $i + 1, $tok);
                }
                continue;
            }
            if ($skipPaths) {
                continue;
            }
            // `src/...` is a pattern in a sentence about paths, not a claim
            // that a directory called `...` exists.
            if (str_contains($tok, '...')) {
                continue;
            }
            if (preg_match('#^(src|tests|tools|build|local|\.github|docs)/[\w./-]+$#', $tok) === 1
                && !file_exists($tok)
            ) {
                $problems[] = sprintf('%s:%d  no such path: %s', $doc, $i + 1, $tok);
            }
        }
    }
}

/** Normalise `a/../b` without requiring the path to exist. */
function realpathish(string $path): string
{
    $out = [];
    foreach (explode('/', $path) as $part) {
        if ($part === '' || $part === '.') {
            continue;
        }
        if ($part === '..') {
            array_pop($out);
            continue;
        }
        $out[] = $part;
    }

    return (str_starts_with($path, '/') ? '/' : '') . implode('/', $out);
}

if ($problems !== []) {
    fwrite(STDERR, sprintf("check-docs: %d broken claim(s):\n", count($problems)));
    foreach ($problems as $p) {
        fwrite(STDERR, '  ' . $p . "\n");
    }
    fwrite(STDERR, "\nFix the doc, or the thing it names. docs/ is part of this codebase:\n");
    fwrite(STDERR, "a reference that goes nowhere costs the next reader more than no\n");
    fwrite(STDERR, "reference at all, because they trust it first.\n");
    exit(1);
}

printf("check-docs: %d files, every link, anchor and path claim resolves.\n", count($docs));
exit(0);
