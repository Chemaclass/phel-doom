<?php

declare(strict_types=1);

// Shared Phel source scanning for the build guards (tools/check-cycles.php,
// tools/check-unused.php).
//
// Both guards have to answer "does this text really appear as CODE" - one for
// requires, one for references - and both are wrong in the same way if they
// count a name that appears in a docstring, a `;` comment or a `#_` discarded
// form. That parser lived in check-cycles.php and had already been fixed twice
// there; a second copy in a second guard would only get one of the fixes.

/**
 * Blank out `;` line comments, `#_` form discards and string bodies, keeping
 * offsets and newlines intact so paren balancing still works on the result.
 */
function stripNonCode(string $code): string
{
    $out = $code;
    $len = strlen($code);
    $inString = false;
    for ($i = 0; $i < $len; $i++) {
        $ch = $code[$i];
        if ($inString) {
            // Newlines survive everywhere, including inside a multi-line
            // docstring: check-unused reports file:line, and flattening them
            // silently shifted every line number after the first long
            // docstring in a file (render/main.phel was off by nine).
            if ($ch === '\\' && $i + 1 < $len) {
                $out[$i] = ' ';
                $out[$i + 1] = $code[$i + 1] === "\n" ? "\n" : ' ';
                $i++;
                continue;
            }
            if ($ch === '"') {
                $inString = false;
            } else {
                $out[$i] = $ch === "\n" ? "\n" : ' ';
            }
            continue;
        }
        if ($ch === '"') {
            $inString = true;
        } elseif ($ch === ';') {
            while ($i < $len && $code[$i] !== "\n") {
                $out[$i] = ' ';
                $i++;
            }
        } elseif ($ch === '#' && $i + 1 < $len && $code[$i + 1] === '|') {
            // #| ... |# block comment, nestable. Without this a fake (ns ...)
            // inside one wins over the real form.
            $out[$i] = ' ';
            $out[$i + 1] = ' ';
            $nest = 1;
            $j = $i + 2;
            for (; $j < $len; $j++) {
                if ($code[$j] === '#' && $j + 1 < $len && $code[$j + 1] === '|') {
                    $nest++;
                    $out[$j] = ' ';
                    $out[$j + 1] = ' ';
                    $j++;
                    continue;
                }
                if ($code[$j] === '|' && $j + 1 < $len && $code[$j + 1] === '#') {
                    $nest--;
                    $out[$j] = ' ';
                    $out[$j + 1] = ' ';
                    $j++;
                    if ($nest === 0) {
                        break;
                    }
                    continue;
                }
                $out[$j] = $code[$j] === "\n" ? "\n" : ' ';
            }
            $i = $j;
        } elseif ($ch === '#' && $i + 1 < $len && $code[$i + 1] === '_') {
            // #_ discards the next form. Stacked discards (#_#_ a b) drop that
            // many forms, so count them first, then skip that many.
            $discards = 0;
            $j = $i;
            while ($j + 1 < $len && $code[$j] === '#' && $code[$j + 1] === '_') {
                $out[$j] = ' ';
                $out[$j + 1] = ' ';
                $j += 2;
                $discards++;
            }
            for ($d = 0; $d < $discards; $d++) {
                $j = skipForm($code, $out, $j, $len);
            }
            $i = $j - 1;
        } elseif ($ch === '#' && $i + 1 < $len && !str_contains('_|{(\"', $code[$i + 1])) {
            // Bare `#` line comment (deprecated but still lexed by Phel).
            while ($i < $len && $code[$i] !== "\n") {
                $out[$i] = ' ';
                $i++;
            }
        }
    }
    return $out;
}


/**
 * Blank one complete form starting at or after $j, returning the offset just
 * past it. Handles (), [] and {} as balanced, anything else as a bare token.
 */
function skipForm(string $code, string &$out, int $j, int $len): int
{
    while ($j < $len && ctype_space($code[$j])) {
        $j++;
    }
    if ($j >= $len) {
        return $j;
    }
    $openers = ['(' => ')', '[' => ']', '{' => '}'];
    if (isset($openers[$code[$j]])) {
        $depth = 0;
        for (; $j < $len; $j++) {
            $c = $code[$j];
            if (isset($openers[$c])) {
                $depth++;
            } elseif (in_array($c, [')', ']', '}'], true)) {
                $depth--;
            }
            $out[$j] = $c === "\n" ? "\n" : ' ';
            if ($depth === 0) {
                return $j + 1;
            }
        }
        return $j;
    }
    for (; $j < $len && !ctype_space($code[$j]) && !in_array($code[$j], [')', ']', '}'], true); $j++) {
        $out[$j] = ' ';
    }
    return $j;
}
