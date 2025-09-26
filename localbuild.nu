#!/usr/bin/env nu

let build_dir = './build_dir'
mkdir $build_dir


# CGO must be enabled to build FrankenPHP
$env.CGO_ENABLED = 1 
$env.XCADDY_SETCAP = 1
$env.XCADDY_GO_BUILD_FLAGS = '-ldflags="-w -s" -trimpath'
$env.GO111MODULE = "on"

let build_args =  [
	--output /usr/local/bin/frankenphp
	--with $"github.com/dunglas/frankenphp=($build_dir)"
	--with $"github.com/dunglas/frankenphp/caddy=($build_dir)/caddy"
	--with github.com/dunglas/caddy-cbrotli
	--with $"github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=($build_dir)/cache"
]

xcaddy build ...$build_args

# /usr/bin/xcaddy build
# 	--output /usr/local/bin/frankenphp
# 	--with github.com/dunglas/frankenphp=/build/
# 	--with github.com/dunglas/frankenphp/caddy=/build/caddy/
# 	--with github.com/dunglas/caddy-cbrotli
# 	--with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=/build/cach
