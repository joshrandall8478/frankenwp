#!/usr/bin/env nu

# This file is to test the spread operator with parenthesis.
let env_args = [
	# Both
	--env CGO_ENABLED=1
	--env XCADDY_SETCAP=1

	# FrankenPHP
	--env XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx"
	--env `CGO_CFLAGS="$(php-config --includes)"`
	--env `CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)"`
]

print $"^bash -c -- echo ...($env_args)"
^bash -c -- echo ...$env_args
