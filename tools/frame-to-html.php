<?php
// ANSI (SGR 256-color + CUP cursor positioning) -> standalone HTML.
// Emulates a terminal cell grid so overlays drawn via \e[r;cH land right.
//
// Usage: php tools/frame-to-html.php COLS ROWS < frame.ans > frame.html
//        tools/frame-shot.sh <script.phel> <out.png>   (the whole pipeline)
//
// Why this is tracked: docs/rendering.md makes visual claims on nearly
// every feature - the message line clears the minimap, the telegraph sits
// above the head, the reticle turns red on a target - and until this file
// moved out of an untracked scratch directory there was no way to CHECK
// any of them from a clean clone. The test suite pins bytes and hashes;
// this pins what the bytes look like.

$COLS = (int)($argv[1] ?? 160);
$ROWS = (int)($argv[2] ?? 40);

function xterm256(int $n): string {
    static $basic = [
        [0,0,0],[205,0,0],[0,205,0],[205,205,0],[0,0,238],[205,0,205],[0,205,205],[229,229,229],
        [127,127,127],[255,0,0],[0,255,0],[255,255,0],[92,92,255],[255,0,255],[0,255,255],[255,255,255],
    ];
    if ($n < 16) { [$r,$g,$b] = $basic[$n]; }
    elseif ($n < 232) {
        $n -= 16;
        $steps = [0,95,135,175,215,255];
        $r = $steps[intdiv($n,36)]; $g = $steps[intdiv($n,6)%6]; $b = $steps[$n%6];
    } else {
        $v = 8 + ($n - 232) * 10; $r = $g = $b = $v;
    }
    return sprintf('#%02x%02x%02x', $r, $g, $b);
}

$input = stream_get_contents(STDIN);

// grid[r][c] = [glyph, fg, bg, bold]
$grid = array_fill(0, $ROWS, array_fill(0, $COLS, [' ', null, null, false]));
$row = 0; $col = 0;
$fg = null; $bg = null; $bold = false;

$tokens = preg_split('/(\e\[[0-9;]*[mHJKABCD])/u', $input, -1, PREG_SPLIT_DELIM_CAPTURE);
foreach ($tokens as $tok) {
    if ($tok === '') continue;
    if (preg_match('/^\e\[([0-9;]*)([mHJKABCD])$/', $tok, $m)) {
        if ($m[2] === 'm') {
            $codes = $m[1] === '' ? [0] : array_map('intval', explode(';', $m[1]));
            for ($i = 0; $i < count($codes); $i++) {
                $c = $codes[$i];
                if ($c === 0) { $fg = $bg = null; $bold = false; }
                elseif ($c === 1) { $bold = true; }
                elseif ($c === 22) { $bold = false; }
                elseif ($c === 39) { $fg = null; }
                elseif ($c === 49) { $bg = null; }
                elseif ($c === 38 && ($codes[$i+1] ?? 0) === 5) { $fg = xterm256($codes[$i+2]); $i += 2; }
                elseif ($c === 48 && ($codes[$i+1] ?? 0) === 5) { $bg = xterm256($codes[$i+2]); $i += 2; }
                elseif ($c === 38 && ($codes[$i+1] ?? 0) === 2) { $fg = sprintf('#%02x%02x%02x', $codes[$i+2] ?? 0, $codes[$i+3] ?? 0, $codes[$i+4] ?? 0); $i += 4; }
                elseif ($c === 48 && ($codes[$i+1] ?? 0) === 2) { $bg = sprintf('#%02x%02x%02x', $codes[$i+2] ?? 0, $codes[$i+3] ?? 0, $codes[$i+4] ?? 0); $i += 4; }
                elseif ($c >= 30 && $c <= 37) { $fg = xterm256($c - 30); }
                elseif ($c >= 90 && $c <= 97) { $fg = xterm256($c - 90 + 8); }
            }
        } elseif ($m[2] === 'H') {
            $p = $m[1] === '' ? [1,1] : array_map('intval', explode(';', $m[1] . ';1'));
            $row = max(0, ($p[0] ?? 1) - 1);
            $col = max(0, ($p[1] ?? 1) - 1);
        }
        elseif ($m[2] === 'C') { $col += max(1, (int)$m[1]); }
        elseif ($m[2] === 'D') { $col -= max(1, (int)$m[1]); if ($col < 0) $col = 0; }
        elseif ($m[2] === 'A') { $row -= max(1, (int)$m[1]); if ($row < 0) $row = 0; }
        elseif ($m[2] === 'B') { $row += max(1, (int)$m[1]); }
        // J/K (clears) ignored: frame paints every cell it owns.
        continue;
    }
    $len = mb_strlen($tok, 'UTF-8');
    for ($i = 0; $i < $len; $i++) {
        $ch = mb_substr($tok, $i, 1, 'UTF-8');
        if ($ch === "\n") { $row++; $col = 0; continue; }
        if ($ch === "\r") { $col = 0; continue; }
        if ($row < $ROWS && $col < $COLS) {
            $grid[$row][$col] = [$ch, $fg, $bg, $bold];
        }
        $col++;
    }
}

// Emit: merge adjacent cells with identical attrs into one span.
$out = [];
foreach ($grid as $cells) {
    $html = ''; $run = ''; $cur = null;
    $flush = function () use (&$html, &$run, &$cur) {
        if ($run === '') return;
        $esc = htmlspecialchars($run, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        [$f, $b, $bo] = $cur;
        $style = '';
        if ($f) $style .= "color:$f;";
        if ($b) $style .= "background:$b;";
        if ($bo) $style .= "font-weight:bold;";
        $html .= $style === '' ? $esc : "<span style=\"$style\">$esc</span>";
        $run = '';
    };
    foreach ($cells as [$ch, $f, $b, $bo]) {
        $attrs = [$f, $b, $bo];
        if ($cur !== null && $attrs !== $cur) $flush();
        $cur = $attrs;
        $run .= $ch;
    }
    $flush();
    $out[] = $html;
}

$body = implode("\n", $out);
echo <<<HTML
<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:#000}
pre{
  margin:0; padding:0;
  font-family:"Menlo","DejaVu Sans Mono",monospace;
  font-size:13px; line-height:15px; letter-spacing:0;
  background:#000; color:#d8d8d8;
}
</style></head><body><pre>$body</pre></body></html>
HTML;
