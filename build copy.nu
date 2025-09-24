#!/usr/bin/env nu

let image_name = "frankenwp"

# TODO: Look into PHP 8.4 
let php_version = "8.3"
let wp_version = "latest"
# let wp_version = "6.8.2-php8.3-fpm"


let frankenphp_builder = buildah from $"dunglas/frankenphp:latest-builder-php($php_version)"
let caddy_builder = buildah from caddy/caddy:builder
let wp = buildah from $"wordpress:($wp_version)"

# Set working dir
buildah config --workingdir /var/www/html $frankenphp_builder

# TODO: fix this
# Copy xcaddy

mkdir /tmp/caddy_builder /tmp/frankenphp_builder

buildah mount $caddy_builder /tmp/caddy_builder
buildah mount $frankenphp_builder /tmp/frankenphp_builder

ls /tmp/caddy_builder
ls /tmp/frankenphp_builder

cp /tmp/caddy_builder/xcaddy /tmp/frankenphp_builder/

umount /tmp/caddy_builder
umount /tmp/frankenphp_builder

return

# Build xcaddy
buildah run $frankenphp_builder 'xcaddy build --output /usr/local/bin/frankenphp --with github.com/dunglas/frankenphp=./ --with github.com/dunglas/frankenphp/caddy=./caddy/ --with github.com/dunglas/caddy-cbrotli --with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=./cache'


# CGO must be enabled to build FrankenPHP
buildah config --env CGO_ENABLED=1 $frankenphp_builder
buildah config --env XCADDY_SETCAP=1 $frankenphp_builder
buildah config --env XCADDY_GO_BUILD_FLAGS='-ldflags="-w -s" -trimpath' $frankenphp_builder

# Install deps
buildah run $frankenphp_builder apt-get update
buildah run $frankenphp_builder apt-get install -y curl tar ca-certificates libxml2-dev



# Permissions
buildah run $frankenphp_builder chown -R www-data:www-data /var/www/html

# Download Caddyfile from frankenwp GitHub repository
buildah run $frankenphp_builder curl -o /etc/caddy/Caddyfile https://raw.githubusercontent.com/dunglas/frankenwp/main/Caddyfile

# Copy mu-plugins to the wp-content volume
buildah copy $frankenphp_builder wp-content/mu-plugins /var/www/html/wp-content/mu-plugins

# Add mysql
buildah run $frankenphp_builder docker-php-ext-install pdo pdo_mysql soap


# Install required PHP extensions for WordPress
buildah run $frankenphp_builder install-php-extensions bcmath exif gd intl mysqli zip imagick/imagick@master opcache

# Expose FrankenPHP default port
buildah config --port 8080 $frankenphp_builder

# Entrypoint/command
buildah config --cmd '["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]' $frankenphp_builder

# Commit the image
buildah commit $frankenphp_builder $"docker-daemon:($image_name):custom"

echo $"✅ Image ($image_name) built successfully"
