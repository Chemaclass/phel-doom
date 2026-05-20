<?php

declare(strict_types=1);

use Phel\Phel;
use PhelGenerated\PhelDoom\Modules\Doom\State;

$projectRootDir = \dirname(__DIR__);

require $projectRootDir . '/vendor/autoload.php';

Phel::run($projectRootDir, 'phel-doom.modules.doom.state');

###################################################
# Run the export command first to (re)generate the
# PHP wrappers from the exported phel functions:
#
#   $ composer export    # or: vendor/bin/phel export
#   $ php example/using-exported-phel-function.php
###################################################
$player = State::new_player(1.5, 1.5, 0.0);

echo 'Player at (' . $player['x'] . ', ' . $player['y'] . ')' . PHP_EOL;
