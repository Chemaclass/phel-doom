<?php

declare(strict_types=1);

// Fail the build on a require cycle between phel-doom namespaces.
//
// tools/check-layers.sh enforces the DIRECTION of dependencies (io/ -> glue/
// -> core/) but is blind to cycles: `core.a -> core.b -> core.a` is two
// legal-looking core->core references and passes its grep cleanly. src/io/ is
// not direction-guarded at all, so an io -> commands edge would close a real
// io -> commands -> io loop with nothing to catch it.
//
// Phel resolves requires at compile time, so a cycle usually surfaces as a
// confusing load error far from its cause - or not at all, when the cycle is
// only reachable through an :as alias. Catching it here keeps the failure
// legible.
//
// Reads only the (ns ...) form of each file, so a namespace named inside a
// docstring or a comment cannot fake an edge.

const SRC_DIR = 'src';

/** Extract the leading `(ns ...)` form, balanced on parens outside strings. */
function nsForm(string $code): string
{
    $start = strpos($code, '(ns ');
    if ($start === false) {
        return '';
    }
    $depth = 0;
    $inString = false;
    $len = strlen($code);
    for ($i = $start; $i < $len; $i++) {
        $ch = $code[$i];
        if ($inString) {
            if ($ch === '\\') {
                $i++;
            } elseif ($ch === '"') {
                $inString = false;
            }
            continue;
        }
        if ($ch === '"') {
            $inString = true;
        } elseif ($ch === '(') {
            $depth++;
        } elseif ($ch === ')') {
            $depth--;
            if ($depth === 0) {
                return substr($code, $start, $i - $start + 1);
            }
        }
    }
    return substr($code, $start);
}

/** @return array<string, list<string>> namespace => required namespaces */
function buildGraph(string $dir): array
{
    $graph = [];
    $files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir));
    foreach ($files as $file) {
        if (!$file->isFile() || $file->getExtension() !== 'phel') {
            continue;
        }
        $code = file_get_contents($file->getPathname());
        if ($code === false) {
            fwrite(STDERR, "check-cycles: cannot read {$file->getPathname()}\n");
            exit(2);
        }
        $ns = nsForm($code);
        if ($ns === '') {
            continue;
        }
        if (!preg_match('/\(ns\s+([^\s()]+)/', $ns, $m)) {
            continue;
        }
        $from = $m[1];
        preg_match_all('/\(:require\s+([^\s()]+)/', $ns, $deps);
        $graph[$from] = array_values(array_unique(array_filter(
            $deps[1],
            static fn (string $to): bool => str_starts_with($to, 'phel-doom.'),
        )));
    }
    return $graph;
}

/** Iterative DFS; returns the first cycle found as a path, or null. */
function findCycle(array $graph): ?array
{
    $state = [];   // ns => 0 unvisited, 1 on stack, 2 done
    $parent = [];

    foreach (array_keys($graph) as $root) {
        if (($state[$root] ?? 0) !== 0) {
            continue;
        }
        $stack = [[$root, 0]];
        $state[$root] = 1;

        while ($stack !== []) {
            [$node, $idx] = array_pop($stack);
            $edges = $graph[$node] ?? [];

            if ($idx < count($edges)) {
                $stack[] = [$node, $idx + 1];
                $next = $edges[$idx];
                $seen = $state[$next] ?? 0;

                if ($seen === 1) {
                    $path = [$next];
                    for ($p = $node; $p !== $next && isset($parent[$p]); $p = $parent[$p]) {
                        $path[] = $p;
                    }
                    $path[] = $next;
                    return array_reverse($path);
                }
                if ($seen === 0 && isset($graph[$next])) {
                    $parent[$next] = $node;
                    $state[$next] = 1;
                    $stack[] = [$next, 0];
                }
            } else {
                $state[$node] = 2;
            }
        }
    }
    return null;
}

if (!is_dir(SRC_DIR)) {
    // Fail loud on a restructure rather than silently passing on an empty graph.
    fwrite(STDERR, "check-cycles: expected directory " . SRC_DIR . " not found (restructure?)\n");
    exit(2);
}

$graph = buildGraph(SRC_DIR);
if ($graph === []) {
    fwrite(STDERR, "check-cycles: parsed 0 namespaces from " . SRC_DIR . " (parser broken?)\n");
    exit(2);
}

$cycle = findCycle($graph);
$edgeCount = array_sum(array_map('count', $graph));

if ($cycle !== null) {
    fwrite(STDERR, "REQUIRE CYCLE: " . implode(" -> ", $cycle) . "\n");
    exit(1);
}

echo sprintf(
    "Cycles OK: %d namespaces, %d internal requires, no cycles.\n",
    count($graph),
    $edgeCount,
);
