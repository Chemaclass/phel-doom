FROM php:8.5-fpm

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y git unzip libzip-dev && \
    docker-php-ext-install zip opcache

RUN { \
        echo 'opcache.enable=1'; \
        echo 'opcache.enable_cli=1'; \
        echo 'opcache.jit=tracing'; \
        echo 'opcache.jit_buffer_size=64M'; \
        echo 'opcache.validate_timestamps=1'; \
    } > /usr/local/etc/php/conf.d/zz-opcache.ini

COPY --from=composer /usr/bin/composer /usr/bin/composer
RUN useradd -m dev
WORKDIR /srv/phel-doom
