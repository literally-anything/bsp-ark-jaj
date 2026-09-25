#!/usr/bin/env bash
# Extension install step: ships the nvpmodel table for this variant's module as
# /etc/nvpmodel.conf (confext), overriding the 16GB table baked into the image.
#
# Both variants share one package list, so the module comes from the name of
# the extension being built: AVOCADO_BUILD_EXT_SYSROOT ends in that name.
set -euo pipefail

die() {
	echo "install-nvpmodel: $*" >&2
	exit 1
}

[ -n "${AVOCADO_BUILD_EXT_SYSROOT:-}" ] || die "AVOCADO_BUILD_EXT_SYSROOT is not set"
[ -n "${AVOCADO_BUILD_DIR:-}" ] || die "AVOCADO_BUILD_DIR is not set"

ext=$(basename "$AVOCADO_BUILD_EXT_SYSROOT")
case "$ext" in
avocado-bsp-ark-jaj-nx16) sku=0000 ;;
avocado-bsp-ark-jaj-nx8) sku=0001 ;;
*) die "don't know which module extension '$ext' is for" ;;
esac

conf="$AVOCADO_BUILD_DIR/nvpmodel_p3767_${sku}_super.conf"
[ -f "$conf" ] || die "$conf missing; did fetch-nvpmodel.sh run?"
install -D -m 0644 "$conf" "$AVOCADO_BUILD_EXT_SYSROOT/etc/nvpmodel.conf"
echo "install-nvpmodel: $ext gets nvpmodel_p3767_${sku}_super.conf"
