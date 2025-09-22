#!/usr/bin/env nu

let image_name = "frankenwp"
let ctr = buildah from dunglas/frankenphp:latest

# Set working dir
buildah config --workingdir /var/www/html $ctr

# Install deps
buildah run $ctr apt-get update
buildah run $ctr apt-get install -y curl tar ca-certificates

# Get WordPress
buildah run $ctr bash -c "curl -o wordpress.tar.gz https://wordpress.org/latest.tar.gz"
buildah run $ctr tar -xzf wordpress.tar.gz --strip-components=1
buildah run $ctr rm wordpress.tar.gz

# Permissions
buildah run $ctr chown -R www-data:www-data /var/www/html

# Download Caddyfile from frankenwp GitHub repository
buildah run $ctr curl -o /etc/caddy/Caddyfile https://raw.githubusercontent.com/dunglas/frankenwp/main/Caddyfile

# Copy mu-plugins to the wp-content volume
buildah copy $ctr wp-content/mu-plugins /var/www/html/wp-content/mu-plugins

# Expose FrankenPHP default port
buildah config --port 8080 $ctr

# Entrypoint/command
buildah config --cmd '["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]' $ctr

# Commit the image
buildah commit $ctr $"docker-daemon:($image_name):custom"

echo $"✅ Image ($image_name) built successfully"
