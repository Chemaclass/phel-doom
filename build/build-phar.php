#!/usr/bin/env php
<?php

declare(strict_types=1);

// Build a single-file, self-contained phel-doom PHAR.
//
// phel-doom is a Phel *application*: `phel build` emits the whole game plus the
// Phel stdlib it touches as ready-to-run PHP under out/, and phar.sh runs
// precompile-stdlib.php to add the stdlib's (load ...) core submodules as
// out/phel/core/*.php siblings (phel build does not harvest those downstream).
// Nothing compiles at runtime, so the archive needs only two trees:
//   out/     - compiled PHP entry point + game code + compiled stdlib
//   vendor/  - the production Phel runtime the compiled code calls into
//
// The whole vendor/ tree is bundled as-is (minus tests/docs), so the working
// tree is never mutated and the composer autoloader stays consistent. The one
// dev dependency (var-dumper, ~200 KB) rides along as harmless dead weight;
// pruning it would require regenerating a --no-dev autoloader, i.e. mutating
// vendor/. The version comes from src/main.phel via `phel build`; nothing is
// stamped here.
//
// Run with: php -d phar.readonly=0 build/build-phar.php [repo-root]

$root = realpath($argv[1] ?? \dirname(__DIR__));
$pharFile = $root . '/build/out/phel-doom.phar';

if (\ini_get('phar.readonly') === '1') {
    fwrite(STDERR, "Error: phar.readonly is on. Run with: php -d phar.readonly=0\n");
    exit(1);
}
if (!is_file($root . '/out/main.php')) {
    fwrite(STDERR, "Error: out/main.php missing — run `phel build` first.\n");
    exit(1);
}

@mkdir(\dirname($pharFile), 0o755, true);
@unlink($pharFile);

// Directory basenames pruned anywhere (tests/docs ship in many vendor packages).
$skipDirs = ['tests' => true, 'Tests' => true, 'test' => true, 'Test' => true,
    'docs' => true, 'doc' => true, '.github' => true];

$phar = new Phar($pharFile);
$phar->startBuffering();

$rootLen = \strlen($root) + 1;
$files = 0;
$sourceBytes = 0;

$addTree = static function (string $dir) use ($root, $rootLen, $skipDirs, $phar, &$files, &$sourceBytes): void {
    $filter = static function (SplFileInfo $cur) use ($skipDirs): bool {
        if ($cur->isDir()) {
            return !isset($skipDirs[$cur->getBasename()]);
        }
        // .phel sources and .map source maps are dead weight at runtime.
        $ext = strtolower($cur->getExtension());
        return $ext !== 'map' && $ext !== 'phel';
    };

    $it = new RecursiveIteratorIterator(
        new RecursiveCallbackFilterIterator(
            new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS),
            $filter,
        ),
    );

    foreach ($it as $f) {
        if (!$f->isFile()) {
            continue;
        }
        $phar->addFile($f->getPathname(), substr($f->getPathname(), $rootLen));
        ++$files;
        $sourceBytes += (int) $f->getSize();
    }
};

$addTree($root . '/out');
$addTree($root . '/vendor');

// Stub maps the PHAR and runs out/main.php, whose own require of
// ../vendor/autoload.php resolves to phar://phel-doom.phar/vendor/autoload.php.
$phar->setStub(
    "#!/usr/bin/env php\n<?php\n"
    . "Phar::mapPhar('phel-doom.phar');\n"
    . "require 'phar://phel-doom.phar/out/main.php';\n"
    . "__HALT_COMPILER();\n",
);

$phar->compressFiles(Phar::GZ);
$phar->setSignatureAlgorithm(Phar::SHA256);
$phar->stopBuffering();
chmod($pharFile, 0o755);

printf(
    "PHAR: %d files, %.2f MB -> %.2f MB (%.0f%% smaller)\n",
    $files,
    $sourceBytes / 1048576,
    filesize($pharFile) / 1048576,
    (1 - filesize($pharFile) / $sourceBytes) * 100,
);
