#!/usr/bin/env nu


# Are we running in the root namespace?
def isRootNamespace []: nothing -> bool {
	let namespace = (
		open /proc/self/uid_map
		| parse --regex '\s*(?<start_uid_namespace>[^\s]+)\s*(?<start_uid_host>[^\s]+)\s*(?<length_uid>[^\s]+)'
		| into int start_uid_namespace start_uid_host length_uid
	)
	mut root_namespace = false
	if ($namespace.start_uid_namespace.0 == 0) and ($namespace.start_uid_host.0 == 0) {
		$root_namespace = true
	}
	use std log
	log info $"namespace: ($namespace)"
	log info $"Root namespace: ($root_namespace)"
	return $root_namespace
}

# Are we running in a container?
# https://forums.docker.com/t/detect-you-are-running-in-a-docker-container-buildx/139673/4
def isContainer []: nothing -> bool {
	let cgroup = (open /proc/1/cgroup | str trim)
	mut container = false
	if ($cgroup == '0::/') {
		$container = true
	}
	use std log
	log info $"cgroup: '($cgroup)'"
	log info $"Container: ($container)"
	return $container
}

# Get the permissions from the seccomp.json.
def get_seccomp [
	--name: string		# Name of permission to get
]: nothing -> string {
	let seccomp = "/usr/share/containers/seccomp.json"
	if not ($seccomp | path exists) {
		use std log
		log error $"File does not exist: '($seccomp)'"
		return ""
	}
	return (open $seccomp | get syscalls | where {$name in $in.names} | get action.0)
}

def check_sysctl []: nothing -> nothing {
	use std log
	let unprivileged_userns_clone = "/proc/sys/kernel/unprivileged_userns_clone"
	if ($unprivileged_userns_clone | path exists) {
		log info $"unprivileged_userns_clone: (open $unprivileged_userns_clone | str trim)"
	} else {
		log info $"unprivileged_userns_clone: Permission does not exist"
	}
}

def build-image [] {
	use std log
	let image_name = "frankenwp"

	# TODO: Look into PHP 8.4 
	let php_version = "8.4"
	let wp_version = "latest"
	# let wp_version = "6.8.2-php8.3-fpm"


	let frankenphp_builder = buildah from $"docker.io/dunglas/frankenphp:builder-php($php_version)"
	let caddy_builder = buildah from docker.io/caddy:builder
	let wp = buildah from $"docker.io/wordpress:($wp_version)"

	let caddy_mnt = (buildah mount $caddy_builder)
	let frankenphp_mnt = (buildah mount $frankenphp_builder)

	mkdir $"($frankenphp_mnt)/build"
	mkdir $"($frankenphp_mnt)/build/cache"
	mkdir $"($frankenphp_mnt)/build/caddy"

	# Set working dir
	buildah config --workingdir /build $frankenphp_builder

	# TODO: fix this
	# Copy xcaddy

	# mkdir /tmp/caddy_builder /tmp/frankenphp_builder

    # print (ls $"($caddy_mnt)/usr/bin")
    # print (ls $frankenphp_mnt)
	print $"caddy_mnt: ($caddy_mnt)"
	print $"frankenphp_mnt: ($frankenphp_mnt)"

	# "path join" does not handle joining mounted directories. Join the directories as a string.
    print ([$caddy_mnt, "/usr/bin/"] | path join)
    print $"($caddy_mnt)/usr/bin/"
    # print (ls $"($caddy_mnt)/usr/bin/")
    #  print (glob $"([$caddy_builder, "/usr/bin/"] | path join)/x*")

	cp $"($caddy_mnt)/usr/bin/xcaddy" $"($frankenphp_mnt)/usr/bin/"

    # print (ls -l $"($frankenphp_mnt)/usr/bin/xcaddy")

	# Copy cache middleware into the build directory
	cp -r ./sidekick/middleware/cache $"($frankenphp_mnt)/build/cache"

	# Build xcaddy in the build directory
	# buildah run $frankenphp_builder 'ls .'
	# return
	let build_cmd =  [
		"/usr/bin/xcaddy build",
		"--output /usr/local/bin/frankenphp",
		"--with github.com/dunglas/frankenphp=/build/",
		"--with github.com/dunglas/frankenphp/caddy=/build/caddy/",
		"--with github.com/dunglas/caddy-cbrotli",
		"--with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=/build/cache"
	] | str join ' '


	# buildah run $frankenphp_builder -- sh -c 'go version'
	buildah run $frankenphp_builder -- sh -c $build_cmd
	log info "xcaddy built"
	return


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

}

# Main script
def main [] {
	use std log

	# 'buildah mount' can not be run in userspace. This script needs to be run as 'buildah unshare build.nu'
	# This detects if we are in the host namespace and runs the script with 'unshare' if we are.
	# https://opensource.com/article/19/3/tips-tricks-rootless-buildah
	# https://unix.stackexchange.com/questions/619664/how-can-i-test-that-a-buildah-script-is-run-under-buildah-unshare
	let is_container = (isContainer)
	let is_root_namespace = (isRootNamespace)
	let unshare_permission = (get_seccomp --name "unshare")
	let clone_permission = (get_seccomp --name "clone")
	log info $"is_container: ($is_container)"
	log info $"is_root_namespace: ($is_root_namespace)"
	log info $"unshare_permission: ($unshare_permission)"
	log info $"clone_permission: ($clone_permission)"

	check_sysctl

	log info "Running 'unshare --user id'"
	try {
		^unshare --user id
	} catch {|err|
		log warning $"Failed to run unshare --user: '($err.msg)'"
	}

	log info "Running 'unshare --mount id'"
	try {
		^unshare --mount id
	} catch {|err|
		log warning $"Failed to run unshare --mount: '($err.msg)'"
	}

	if ($is_container) {
		log info "Detected container. Using chroot isolation."
		$env.BUILDAH_ISOLATION = "chroot"
	} else if ($is_root_namespace) {
		# unshare cannot be run in certain environments.
		# https://github.com/containers/buildah/issues/1901
		# Dockers/containerd blocks unshare and mount. Podman, Buildah, CRI-O do not.
		log info "Detected root namespace and not in container. Rerunning in a 'buildah unshare' environment."
		^buildah unshare ./build.nu
		exit 0
	}

	# Build the image using buildah in a root namespace.
	build-image

}
