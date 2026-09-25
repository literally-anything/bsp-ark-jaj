#!/usr/bin/env bash
# Runs a repo script in Ubuntu 24.04, whose dtc (1.7.0) matches the Avocado
# 2024 SDK's. build-carrier-bsp.sh refuses other dtc versions, so use this on
# hosts that have a newer one (macOS Homebrew ships 1.8):
#
#   scripts/in-container.sh scripts/build-carrier-bsp.sh [--check]
#
# The repo is copied in (no bind mount, so it works with a remote Docker such
# as the avocado-vm's). build/ (git-ignored: download cache, built DTB) is
# copied back, and so are stone/ and overlays/ unless the script ran with
# --check. Uses $DOCKER_HOST, or the avocado-vm's socket when the default one
# isn't there.
set -euo pipefail

cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { echo "usage: $0 <script> [args...]" >&2; exit 2; }

if [ -z "${DOCKER_HOST:-}" ] && ! docker info >/dev/null 2>&1 && [ -S "$HOME/.avocado/vm/docker.sock" ]; then
	export DOCKER_HOST="unix://$HOME/.avocado/vm/docker.sock"
fi

copy_back=true
for arg in "$@"; do [ "$arg" = --check ] && copy_back=false; done

args=$(printf '%q ' "$@")
out=$(mktemp)
trap 'rm -f "$out"' EXIT
COPYFILE_DISABLE=1 tar -cf - --exclude ./.git --exclude ./.avocado . |
	docker run --rm -i ubuntu:24.04 bash -c "
		set -e
		apt-get update -qq >/dev/null
		DEBIAN_FRONTEND=noninteractive apt-get install -y -qq device-tree-compiler cpp libarchive-tools curl perl ca-certificates >/dev/null 2>&1
		mkdir /repo && cd /repo && tar -xf - 2>/dev/null
		$args >&2
		if $copy_back; then tar -cf - stone overlays build; else tar -cf - build; fi
	" >"$out"

$copy_back && rm -rf stone
tar -xf "$out"
