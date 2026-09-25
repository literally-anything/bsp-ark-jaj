#!/usr/bin/env bash
# Proves the committed kernel DTB is exactly what Avocado's own overlay support
# will produce once the overlays are declared as device_tree_overlays.
#
# Runs meta-avocado's real avocado-dtc-overlay (the compiler avocado-cli calls)
# and the Tegra device-tree-overlay-deliver hook (the merge), both at
# META_AVOCADO_COMMIT, inside this repo's Avocado SDK with the SDK's own dtc, on
# the x-device-tree-overlays list and the pinned flash BSP. Then compares the
# merged DTB with the one scripts/build-carrier-bsp.sh built (build/, and
# committed in stone/carrier-bsp/ until the switch to device_tree_overlays).
#
# Needs an installed SDK: avocado sdk install --target jetson-orin-nx
#
# Usage: scripts/check-avocado-hook.sh
set -euo pipefail

cd "$(dirname "$0")/.."
. ./upstream.env

die() {
	echo "check-avocado-hook: $*" >&2
	exit 1
}

WORK=build/hook-check
COMMITTED=build/tegra234-p3768-0000+p3767-0000-nv-super-ark-jaj.dtb

if [ "${1:-}" != --in-sdk ]; then
	# --- host side: fetch the scripts, stage the stock BSP files -----------
	rpm="build/cache/$BOOTFILES_SHA256.rpm"
	[ -f "$rpm" ] && [ -f "$COMMITTED" ] \
		|| die "run scripts/build-carrier-bsp.sh (or scripts/in-container.sh scripts/build-carrier-bsp.sh --check) first"
	rm -rf "$WORK"
	mkdir -p "$WORK/data" "$WORK/kdir"
	curl -fsSL "$META_AVOCADO_REPO/$META_AVOCADO_COMMIT/meta-avocado-shared/recipes-avocado/avocado-dtc-overlay/files/avocado-dtc-overlay" \
		-o "$WORK/avocado-dtc-overlay"
	curl -fsSL "$META_AVOCADO_REPO/$META_AVOCADO_COMMIT/meta-avocado-nvidia/recipes-avocado/avocado-dtc-overlay-deliver/files/device-tree-overlay-deliver" \
		-o "$WORK/device-tree-overlay-deliver"
	chmod +x "$WORK/avocado-dtc-overlay" "$WORK/device-tree-overlay-deliver"
	bsdtar -xf "$rpm" -C "$WORK/data" ./tegraflash-bsp/.env.initrd-flash \
		./tegraflash-bsp/tegra234-p3768-0000+p3767-0000-nv-super.dtb
	# kernel-devsrc stand-in: the same Linux dt-bindings headers.
	cp -R src/include "$WORK/kdir/include"
	exec avocado sdk run --target jetson-orin-nx -- /opt/src/scripts/check-avocado-hook.sh --in-sdk
fi

# --- SDK side ---------------------------------------------------------------
# `sdk run` doesn't set up the toolchain environment; builds do.
. "$AVOCADO_SDK_PREFIX/environment-setup"
export PATH="$AVOCADO_SDK_PREFIX/usr/bin:$PATH"
W=/opt/src/$WORK
ST=$W/staging
mkdir -p "$ST"

manifest='{"version":1,"overlays":['
sep=
while read -r name src; do
	"$W/avocado-dtc-overlay" --name "$name" --src "/opt/src/$src" --out "$ST/$name.dtbo" --kdir "$W/kdir" 2>&1 |
		grep -v 'Warning (' || true
	[ -f "$ST/$name.dtbo" ] || die "avocado-dtc-overlay failed for $name"
	manifest="$manifest$sep{\"name\":\"$name\",\"file\":\"$name.dtbo\",\"params\":{},\"claimed_by\":null}"
	sep=,
done < <(perl -ne '
	if (/^x-device-tree-overlays:/) { $in = 1; next }
	if ($in && /^\S/) { last }
	$name = $1 if $in && /^\s*-\s*name:\s*(\S+)/;
	print "$name $1\n" if $in && /^\s*src:\s*(\S+)/;
' /opt/src/avocado.yaml)
echo "$manifest]}" >"$ST/overlays.manifest.json"

AVOCADO_DTBO_STAGING="$ST" \
AVOCADO_OVERLAYS_MANIFEST="$ST/overlays.manifest.json" \
AVOCADO_DELIVERY_FRAGMENT="$ST/delivery.overlay.json" \
AVOCADO_STONE_MANIFEST="$AVOCADO_SDK_PREFIX/stone/stone-jetson-orin-nx.json" \
AVOCADO_STONE_DATA_DIR="$W/data" \
	"$W/device-tree-overlay-deliver"

merged="$ST/tegra234-p3768-0000+p3767-0000-nv-super.dtb"
[ -f "$merged" ] || die "the hook published no merged DTB"
if ! diff <(dtc -q -I dtb -O dts -s "$merged") <(dtc -q -I dtb -O dts -s "/opt/src/$COMMITTED") >"$W/diff.txt"; then
	head -40 "$W/diff.txt" >&2
	die "Avocado's overlay hook produces a different DTB than build-carrier-bsp.sh ($COMMITTED, $(dtc --version))"
fi
echo "check-avocado-hook: Avocado's overlay hook ($(dtc --version | sed 's/^Version: //')) produces exactly $COMMITTED, the DTB build-carrier-bsp.sh built"
