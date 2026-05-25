<?php

declare(strict_types=1);

use Phel\Config\PhelConfig;

return PhelConfig::forProject(mainNamespace: 'phel-doom.main')
    ->withMainPhpPath('out/main.php')
    ->withIgnoreWhenBuilding(['local.phel']);
