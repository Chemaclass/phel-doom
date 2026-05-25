# Minimal image to run phel-doom without installing PHP / Composer
# locally. Build:    docker build -t phel-doom .
# Run:              docker run --rm -it phel-doom
#
# The image bundles PHP 8.5 CLI, Composer, and a `composer install`
# of phel-lang + symfony/console. `make play` is the default CMD;
# `-it` keeps the terminal in raw mode so ANSI render + key input
# work the same as a host run.
FROM php:8.5-cli-alpine

RUN apk add --no-cache git unzip bash && \
    curl -sS https://getcomposer.org/installer | php -- \
        --install-dir=/usr/local/bin --filename=composer

WORKDIR /app

# Copy manifests first so the Composer layer caches when only source
# changes between builds.
COPY composer.json composer.lock* /app/
RUN composer install --no-interaction --no-progress --no-scripts

COPY . /app

# Default entrypoint: launch the game. Override with e.g.
#   docker run --rm -it phel-doom vendor/bin/phel test
ENTRYPOINT ["vendor/bin/phel"]
CMD ["run", "phel-doom.main", "play"]
