#!/usr/bin/env php
<?php

declare(strict_types=1);

// Precompile the Phel stdlib's `(load ...)` core submodules into PHAR-ready
// `.php` siblings under out/phel/core/.
//
// Since phel 0.46, `phel.core` is split into submodules (core/meta, core/math,
// …) pulled in at runtime via `(load "core/X")`. A downstream `phel build`
// compiles out/phel/core.php but does NOT harvest those secondaries into
// out/phel/core/*.php, so a self-contained PHAR ships core.php without its
// siblings and the first `(load ...)` fatals (LoadClasspath is empty in a PHAR,
// and a bare game PHAR has no compiler bootstrap to recompile on the fly).
//
// phel's own phel.phar avoids this by building `phel.core` from source and
// harvesting the siblings (build/build-phar.php::addPrecompiledStdlibSiblings).
// We reproduce that here: bootstrap Phel against the vendored phel-lang copy
// (its config already targets `phel.core` over src/phel) and compile it, which
// emits the harvested submodules under <vendor>/out/phel/core/. We then copy
// just that subtree next to phel-doom's own out/phel/core.php.
//
// Downstream workaround for phel-lang#2648 (drop this once it ships a fix).

use Phel\Build\BuildFacade;
use Phel\Build\Domain\Compile\BuildOptions;
use Phel\Phel;

$root = realpath($argv[1] ?? \dirname(__DIR__));
require $root . '/vendor/autoload.php';

$vendorRoot = realpath($root . '/vendor/phel-lang/phel-lang');
if ($vendorRoot === false) {
    fwrite(STDERR, "Error: vendored phel-lang not found under vendor/.\n");
    exit(1);
}

$srcCoreDir = $vendorRoot . '/src/phel/core';
$vendorOutDir = $vendorRoot . '/out';
$vendorOutCoreDir = $vendorOutDir . '/phel/core';
$destCoreDir = $root . '/out/phel/core';

$rmTree = static function (string $dir) use (&$rmTree): void {
    if (!is_dir($dir)) {
        return;
    }
    foreach (new DirectoryIterator($dir) as $f) {
        if ($f->isDot()) {
            continue;
        }
        $f->isDir() ? $rmTree($f->getPathname()) : @unlink($f->getPathname());
    }
    @rmdir($dir);
};

if (!is_file($root . '/out/phel/core.php')) {
    fwrite(STDERR, "Error: out/phel/core.php missing — run `phel build` first.\n");
    exit(1);
}

// Compile into the vendor tree, then remove it: build-phar.php bundles all of
// vendor/, so a leftover out/ would ship a duplicate stdlib in the PHAR.
$rmTree($vendorOutDir);
if (!mkdir($vendorOutDir, 0o755, true) && !is_dir($vendorOutDir)) {
    fwrite(STDERR, "Error: cannot create {$vendorOutDir}.\n");
    exit(1);
}

// Match phel-doom's own optimization level (phel-config.php) so the siblings
// are emitted identically to the primary they sit next to.
Phel::bootstrap($vendorRoot);
(new BuildFacade())->compileProject(new BuildOptions(
    enableCache: false,
    enableSourceMap: false,
    optimizationLevel: 2,
));

if (!is_dir($vendorOutCoreDir)) {
    fwrite(STDERR, "Error: expected harvested submodules at {$vendorOutCoreDir}, none found.\n");
    exit(1);
}

@mkdir($destCoreDir, 0o755, true);

$expected = 0;
foreach (new DirectoryIterator($srcCoreDir) as $f) {
    if ($f->isFile() && strtolower($f->getExtension()) === 'phel') {
        ++$expected;
    }
}

$copied = 0;
foreach (new DirectoryIterator($vendorOutCoreDir) as $f) {
    if (!$f->isFile() || strtolower($f->getExtension()) !== 'php') {
        continue;
    }
    if (!copy($f->getPathname(), $destCoreDir . '/' . $f->getFilename())) {
        fwrite(STDERR, "Error: failed to copy {$f->getFilename()} sibling.\n");
        exit(1);
    }
    ++$copied;
}

if ($copied < $expected) {
    fwrite(STDERR, "Error: copied {$copied} submodule(s), expected {$expected}.\n");
    exit(1);
}

$rmTree($vendorOutDir);

printf("Stdlib siblings: %d precompiled into out/phel/core/\n", $copied);
