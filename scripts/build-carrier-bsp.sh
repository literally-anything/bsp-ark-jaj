#!/usr/bin/env bash
# Generates the committed build outputs from the pinned inputs in upstream.env:
#
#   overlays/ (derived files)  from ARK's sources in src/ark:
#       jaj-hdmi-dcb.dtsi                    the HDMI DCB blob, as a property
#       jaj-imx219-dual.dtso                 ARK's dual IMX219 camera overlay
#       tegra234-camera-rbpcv2-imx219.dtsi   its include, unchanged
#   stone/carrier-bsp/                   the flash-time carrier files:
#       tegra234-p3768-0000+p3767-0000-nv-super-ark-jaj.dtb
#           Avocado's stock DTB with the overlays listed under
#           x-device-tree-overlays in avocado.yaml applied, compiled and merged
#           the way avocado-cli's avocado-dtc-overlay and the Tegra
#           device-tree-overlay-deliver hook do it
#       tegra234-mb1-bct-{pinmux,gpio}-p3767-dp-a03-ark-jaj.dtsi   ARK's
#       tegra234-mb2-bct-misc-p3767-0000-ark-jaj.dts   stock, no carrier EEPROM
#       ark-jaj-boot-order.dtbo              ARK's UEFI boot order
#       carrier.env                          points the flash at all of the above
#
# Both are committed: a fetched extension's stone/ is copied as-is, and the
# overlay sources are what avocado-cli will compile once the Jetson overlay
# hook ships (README.md, "Switching to device_tree_overlays").
#
# Usage:
#   scripts/build-carrier-bsp.sh            regenerate
#   scripts/build-carrier-bsp.sh --check    regenerate into a temp dir and fail
#                                           if anything differs from what's committed
#   scripts/build-carrier-bsp.sh --drift    fail if the feed's newest snapshot
#                                           ships a different flash BSP than the pin
#
# Needs: dtc, fdtoverlay, fdtget, a C preprocessor (cc or cpp), bsdtar, curl,
# perl, sha256sum or shasum. On Debian/Ubuntu: device-tree-compiler cpp
# libarchive-tools curl. On macOS: brew install dtc.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
. ./upstream.env

die() {
	echo "build-carrier-bsp: $*" >&2
	exit 1
}
info() {
	echo "build-carrier-bsp: $*"
}

MODE=build
case "${1:-}" in
"") ;;
--check) MODE=check ;;
--drift) MODE=drift ;;
*) die "unknown argument '$1' (see the header of this script)" ;;
esac

for tool in curl perl gzip; do
	command -v "$tool" >/dev/null || die "$tool not found"
done
if [ "$MODE" != drift ]; then
	for tool in dtc fdtoverlay fdtget bsdtar; do
		command -v "$tool" >/dev/null || die "$tool not found"
	done
	# The committed DTB must be what Avocado's Tegra overlay hook will produce,
	# and the hook runs the SDK's dtc (1.7.0 for 2024). dtc/libfdt versions
	# differ in how fdtoverlay treats phandles on labelled overlay nodes (1.7.0
	# renumbers the lane nodes' phandles, 1.7.1+ keeps them), so another version
	# builds an equivalent but different blob. scripts/in-container.sh runs this
	# script with Ubuntu 24.04's dtc 1.7.0, which is what CI uses too.
	dtc_version=$(dtc --version | sed -n 's/^Version: DTC v\{0,1\}\([0-9]*\.[0-9]*\).*/\1/p')
	[ "$dtc_version" = 1.7 ] \
		|| die "dtc $dtc_version found, but the outputs must be built with dtc 1.7.x like the Avocado 2024 SDK's; run: scripts/in-container.sh scripts/build-carrier-bsp.sh ${1:-}"
	# C preprocessor: $CC -E if there's a compiler, else a bare cpp.
	if command -v "${CC:-cc}" >/dev/null; then
		PP=("${CC:-cc}" -E)
	elif command -v cpp >/dev/null; then
		PP=(cpp)
	else
		die "no C preprocessor (cc or cpp) found"
	fi
fi
if command -v sha256sum >/dev/null; then
	sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
	sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
	die "sha256sum or shasum not found"
fi

FEED="$AVOCADO_REPO_URL/$AVOCADO_RELEASE/$AVOCADO_CHANNEL"

# Newest avocado-img-bootfiles in a snapshot's primary.xml, as "<sha256>".
bootfiles_in_snapshot() {
	local base="$FEED/snapshots/$1/target/$AVOCADO_TARGET" primary
	primary=$(curl -fsSL "$base/repodata/repomd.xml" | grep -o 'repodata/[^"]*-primary\.xml\.gz' | head -n 1) \
		|| die "no repodata for snapshot $1 at $base"
	curl -fsSL "$base/$primary" | gzip -dc | perl -0777 -ne '
		my ($best, $bestrel);
		while (/<package type="rpm">(.*?)<\/package>/sg) {
			my $p = $1;
			next unless $p =~ m{<name>avocado-img-bootfiles</name>};
			my ($rel) = $p =~ m{<version [^>]*rel="r0\.(\d+)"};
			my ($sum) = $p =~ m{<checksum type="sha256"[^>]*>(\w+)<};
			($best, $bestrel) = ($sum, $rel) if !defined $bestrel || $rel > $bestrel;
		}
		print "$best\n" if defined $best;'
}

if [ "$MODE" = drift ]; then
	latest=$(curl -fsSL "$FEED/target/$AVOCADO_TARGET/snapshots-latest.json" | perl -ne 'print $1 if /"id":\s*"?(\d+)/')
	[ -n "$latest" ] || die "could not read the latest snapshot id"
	sum=$(bootfiles_in_snapshot "$latest")
	[ -n "$sum" ] || die "snapshot $latest has no avocado-img-bootfiles"
	if [ "$sum" != "$BOOTFILES_SHA256" ]; then
		die "snapshot $latest ships a different flash BSP ($sum) than the pinned one (snapshot $AVOCADO_SNAPSHOT, $BOOTFILES_SHA256). Set AVOCADO_SNAPSHOT=$latest and BOOTFILES_SHA256=$sum in upstream.env, rerun this script and review the DTB diff."
	fi
	info "snapshot $latest still ships the pinned flash BSP"
	exit 0
fi

# ---------------------------------------------------------------------------
# Fetch the pinned flash BSP (content-addressed, so the hash is the name).
# ---------------------------------------------------------------------------
CACHE="$ROOT/build/cache"
mkdir -p "$CACHE"
rpm="$CACHE/$BOOTFILES_SHA256.rpm"
if [ ! -f "$rpm" ] || [ "$(sha256 "$rpm")" != "$BOOTFILES_SHA256" ]; then
	info "downloading avocado-img-bootfiles ($BOOTFILES_SHA256)"
	curl -fSL "$FEED/_pkgs/${BOOTFILES_SHA256:0:2}/$BOOTFILES_SHA256.rpm" -o "$rpm.part"
	mv "$rpm.part" "$rpm"
fi
[ "$(sha256 "$rpm")" = "$BOOTFILES_SHA256" ] || die "$rpm does not match BOOTFILES_SHA256"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BSP="$WORK/tegraflash-bsp"
stock_files=(
	flashvars
	.env.initrd-flash
	tegra234-p3768-0000+p3767-0000-nv-super.dtb
	tegra234-mb2-bct-misc-p3767-0000.dts
	tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi
	L4TConfiguration.dtbo
	L4TConfiguration-RootfsRedundancyLevelABEnable.dtbo
)
patterns=()
for f in "${stock_files[@]}"; do patterns+=("./tegraflash-bsp/$f"); done
bsdtar -xf "$rpm" -C "$WORK" "${patterns[@]}" || die "flash BSP is missing one of: ${stock_files[*]}"
for f in "${stock_files[@]}"; do
	[ -f "$BSP/$f" ] || die "flash BSP is missing $f"
done

# Keys a carrier.env may retarget must already exist, or the provision script
# only prints a WARNING and flashes the stock value.
flashvar() {
	grep -q "^$1=" "$BSP/flashvars" || die "flashvars has no $1"
	sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$BSP/flashvars"
}
envvar() {
	grep -q "^$1=" "$BSP/.env.initrd-flash" || die ".env.initrd-flash has no $1"
	sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$BSP/.env.initrd-flash"
}

# This repo layers onto the jetson-orin-nx MACHINE's SKU-0000 (16GB, Super)
# defaults, and the Tegra overlay hook merges into the DTB .env.initrd-flash
# names. If Avocado changes either, stop and look.
BASE_DTB=tegra234-p3768-0000+p3767-0000-nv-super.dtb
[ "$(flashvar CHECK_BOARDSKU)" = 0000 ] || die "the pinned BSP no longer defaults to SKU 0000"
[ "$(envvar DTBFILE)" = "$BASE_DTB" ] || die "the pinned BSP no longer boots $BASE_DTB"
[ "$(flashvar PINMUX_CONFIG)" = tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi ] || die "stock PINMUX_CONFIG changed"
[ "$(flashvar MB2BCT_CFG)" = tegra234-mb2-bct-misc-p3767-0000.dts ] || die "stock MB2BCT_CFG changed"
STOCK_OVERLAYS=$(flashvar BOOTCONTROL_OVERLAYS)
[ -n "$STOCK_OVERLAYS" ] || die "stock BOOTCONTROL_OVERLAYS is empty"
flashvar CHECK_BOARDID >/dev/null

# jaj-lane-labels.dtso can renumber the XUSB lane nodes' phandles (see the dtc
# note above). That's only safe because the two USB controllers are the only
# nodes that point at those lanes, and jaj-carrier.dtso rewrites both. Check
# that still holds for this BSP.
lane_refs=$(dtc -q -I dtb -O dts "$BSP/$BASE_DTB" | perl -ne '
	BEGIN { %lanes = map { $_ => 1 } @ARGV; @ARGV = () }
	$path = $1 if /^\s*([\w@,.-]+) \{$/;
	if (/^\s*phys = <([^>]*)>;/) { for (split " ", $1) { if ($lanes{$_}) { print "$path\n"; last } } }
' $(for l in usb2/lanes/usb2-0 usb2/lanes/usb2-1 usb2/lanes/usb2-2 usb3/lanes/usb3-0 usb3/lanes/usb3-1; do
	printf '0x%s ' "$(fdtget -tx "$BSP/$BASE_DTB" "/bus@0/padctl@3520000/pads/$l" phandle)"
done) | sort -u | tr '\n' ' ')
[ "$lane_refs" = "usb@3550000 usb@3610000 " ] \
	|| die "the stock DTB references the XUSB lanes from '$lane_refs', not just the two USB controllers; jaj-lane-labels.dtso may break them"

# ---------------------------------------------------------------------------
# Derived overlay sources (from ARK's files in src/ark)
# ---------------------------------------------------------------------------
OVL_OUT="$WORK/overlays"
mkdir -p "$OVL_OUT"

# The DCB blob as a bare property, for jaj-carrier.dtso to #include inside its
# &{/display@13800000} node. ARK's file wraps it in a full-tree `/ { ... }`,
# which an overlay can't use.
{
	echo "// SPDX-License-Identifier: GPL-2.0-only"
	echo "// SPDX-FileCopyrightText: Copyright (c) 2021-2023, NVIDIA CORPORATION & AFFILIATES.  All rights reserved."
	echo "// Generated by scripts/build-carrier-bsp.sh from src/ark/tegra234-dcb-p3737-0000-p3701-0000-hdmi.dtsi. Do not edit."
	awk '/nvidia,dcb-image = \[/ {on = 1} on {print} on && /\];$/ {exit}' \
		"$ROOT/src/ark/tegra234-dcb-p3737-0000-p3701-0000-hdmi.dtsi"
} >"$OVL_OUT/jaj-hdmi-dcb.dtsi"
grep -q '];$' "$OVL_OUT/jaj-hdmi-dcb.dtsi" || die "could not extract nvidia,dcb-image from ARK's DCB file"

# ARK's camera overlay, with NVIDIA's compatible-list header (not in
# kernel-devsrc) swapped for this repo's stand-in next to it.
cp "$ROOT/src/ark/tegra234-camera-rbpcv2-imx219.dtsi" "$OVL_OUT/"
perl -pe 's{^#include <dt-bindings/tegra234-p3767-0000-common\.h>}{#include "jetson-compatible.h"}' \
	"$ROOT/src/ark/tegra234-p3767-camera-p3768-imx219-dual.dts" >"$OVL_OUT/jaj-imx219-dual.dtso"
grep -q '#include "jetson-compatible.h"' "$OVL_OUT/jaj-imx219-dual.dtso" \
	|| die "ARK's camera overlay no longer includes tegra234-p3767-0000-common.h"

# Everything the overlays are compiled from: hand-written + derived.
OVL_SRC="$WORK/overlay-src"
mkdir -p "$OVL_SRC"
cp "$ROOT"/overlays/*.dtso "$ROOT"/overlays/*.h "$OVL_SRC/"
cp "$OVL_OUT"/* "$OVL_SRC/"

# ---------------------------------------------------------------------------
# Kernel DTB: stock + overlays
# ---------------------------------------------------------------------------
# The list, from avocado.yaml's x-device-tree-overlays (name/src pairs).
mapfile -t OVERLAYS < <(perl -ne '
	if (/^x-device-tree-overlays:/) { $in = 1; next }
	if ($in && /^\S/) { last }
	if ($in && /^\s*-\s*name:\s*(\S+)/) { $name = $1 }
	if ($in && /^\s*src:\s*overlays\/(\S+)/) { print "$name $1\n" }
' avocado.yaml)
[ "${#OVERLAYS[@]}" -gt 0 ] || die "no x-device-tree-overlays list in avocado.yaml"

# Compile one .dtso as avocado-dtc-overlay does: cpp only if it #includes, with
# only the kernel's dt-bindings on the include path, then dtc -@ -i <src dir>.
compile_overlay() {
	local src=$1 out=$2 dts=$1
	grep -Eq '^[[:space:]]*/plugin/[[:space:]]*;' "$src" || die "$(basename "$src") is missing /plugin/;"
	if grep -Eq '^[[:space:]]*#[[:space:]]*include' "$src"; then
		dts="$WORK/$(basename "$src").pp"
		"${PP[@]}" -nostdinc -undef -x assembler-with-cpp -D__DTS__ \
			-I "$ROOT/src/include" "$src" -o "$dts" || die "preprocessing $(basename "$src") failed"
	fi
	dtc -q -@ -I dts -O dtb -i "$(dirname "$src")" -o "$out" "$dts" || die "dtc failed on $(basename "$src")"
}

DTBOS=()
for entry in "${OVERLAYS[@]}"; do
	read -r name file <<<"$entry"
	[ -f "$OVL_SRC/$file" ] || die "overlay $name: overlays/$file not found"
	compile_overlay "$OVL_SRC/$file" "$WORK/$name.dtbo"
	DTBOS+=("$WORK/$name.dtbo")
done

# Once the extension itself declares `device_tree_overlays: *jaj_overlays`,
# Avocado's hook builds and publishes the merged DTB, so carrier-bsp/ must stop
# shipping one. The DTB is still built here, to run the checks below.
HOOK_DELIVERS=false
if grep -Eq '^[[:space:]]+device_tree_overlays:[[:space:]]*\*jaj_overlays' avocado.yaml; then
	HOOK_DELIVERS=true
fi

SLOT="$WORK/stone/carrier-bsp"
mkdir -p "$SLOT"
DTB=tegra234-p3768-0000+p3767-0000-nv-super-ark-jaj.dtb
# One fdtoverlay call, in list order, as the hook does: later overlays resolve
# labels that earlier ones added (jaj-lane-labels -> jaj-carrier).
fdtoverlay -i "$BSP/$BASE_DTB" -o "$SLOT/$DTB" "${DTBOS[@]}" || die "fdtoverlay failed"

# Spot-check that each part of the JAJ delta landed.
expect() { # <fdtget type> <node> <property> <expected>
	local got
	got=$(fdtget -t "$1" "$SLOT/$DTB" "$2" "$3" 2>/dev/null) || die "$2 $3 missing"
	[ "$got" = "$4" ] || die "$2 $3 is '$got', expected '$4'"
}
expect s / model "NVIDIA Jetson Orin NX 16GB ARK JAJ Jetson Carrier Super"
expect s /aliases serial3 /bus@0/serial@3110000
expect s /bus@0/serial@3110000 compatible nvidia,tegra194-hsuart
expect s /bus@0/serial@3110000 status okay
expect s /bus@0/serial@3100000 dma-names "unused-rx unused-tx"
expect s /bus@0/padctl@3520000/pads/usb3/lanes/usb3-2 status okay
expect s /bus@0/padctl@3520000/ports/usb3-2 status okay
expect s /bus@0/usb@3550000 phy-names "usb2-0 usb3-0"
lane=$(fdtget -tx "$SLOT/$DTB" /bus@0/padctl@3520000/pads/usb3/lanes/usb3-0 phandle)
gadget_phys=$(fdtget -tx "$SLOT/$DTB" /bus@0/usb@3550000 phys)
[ "${gadget_phys##* }" = "$lane" ] || die "USB-C gadget isn't on the usb3-0 lane"
[ "$(fdtget -tx "$SLOT/$DTB" /bus@0/usb@3610000 phys | wc -w)" -eq 6 ] || die "host controller doesn't have 6 phys"
expect u /bus@0/pcie@141e0000 max-link-speed 2
expect s /bus@0/hda@3510000 status okay
expect u /display@13800000 os_gpio_hotplug_a "$(fdtget -tu "$BSP/$BASE_DTB" /display@13800000 os_gpio_hotplug_a | awk '{print $1, $2, 1}')"
[ "$(fdtget -tx "$SLOT/$DTB" /display@13800000 nvidia,dcb-image | head -c 11)" = "55 aa 16 0 " ] \
	|| [ "$(fdtget -tbx "$SLOT/$DTB" /display@13800000 nvidia,dcb-image | head -c 11)" = "55 aa 16 00" ] \
	|| die "HDMI DCB image not applied"
expect s /bus@0/cam_i2cmux status okay
expect s /bus@0/cam_i2cmux/i2c@0/rbpcv2_imx219_a@10 compatible sony,imx219
expect s /bus@0/cam_i2cmux/i2c@1/rbpcv2_imx219_c@10 compatible sony,imx219

# ---------------------------------------------------------------------------
# Bootloader configuration and UEFI defaults
# ---------------------------------------------------------------------------
dtc -q -I dts -O dtb -o "$SLOT/ark-jaj-boot-order.dtbo" "$ROOT/src/ark/ark_boot_order.dts"

# Pinmux + GPIO: ARK's files, renamed so the flash log shows whose they are.
# The pinmux #includes the GPIO file by name; retarget that one line (CRLF kept).
PINMUX=tegra234-mb1-bct-pinmux-p3767-dp-a03-ark-jaj.dtsi
GPIO=tegra234-mb1-bct-gpio-p3767-dp-a03-ark-jaj.dtsi
cp "$ROOT/src/ark/tegra234-mb1-bct-gpio-p3767-dp-a03.dtsi" "$SLOT/$GPIO"
perl -pe 's{^(#include "\./)tegra234-mb1-bct-gpio-p3767-dp-a03\.dtsi(")}{$1'"$GPIO"'$2}' \
	"$ROOT/src/ark/tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi" >"$SLOT/$PINMUX"
[ "$(grep -c "#include \"./$GPIO\"" "$SLOT/$PINMUX")" -eq 1 ] || die "could not retarget the GPIO #include in ARK's pinmux"
if grep -q 'tegra234-mb1-bct-gpio-p3767-dp-a03\.dtsi' "$SLOT/$PINMUX"; then
	die "ARK's pinmux still includes the stock GPIO file"
fi

# MB2 misc: stock file with only the carrier EEPROM read disabled.
MB2=tegra234-mb2-bct-misc-p3767-0000-ark-jaj.dts
perl -pe 's{^(\s*cvb_eeprom_read_size = )<0x100>;}{$1<0x0>;}' \
	"$BSP/tegra234-mb2-bct-misc-p3767-0000.dts" >"$SLOT/$MB2"
[ "$(diff "$BSP/tegra234-mb2-bct-misc-p3767-0000.dts" "$SLOT/$MB2" | grep -c '^>')" -eq 1 ] \
	|| die "expected exactly one change (cvb_eeprom_read_size) in the stock MB2 misc BCT"

# Always kept in build/ (not committed) for scripts/check-avocado-hook.sh.
mkdir -p "$ROOT/build"
cp "$SLOT/$DTB" "$ROOT/build/$DTB"
if $HOOK_DELIVERS; then
	DTB_ENV="# Kernel DTB: built by Avocado's device-tree overlay hook from device_tree_overlays."
	rm "$SLOT/$DTB"
else
	DTB_ENV="# Kernel DTB: stock + this repo's device-tree overlays, until Avocado's
# overlay hook builds it from device_tree_overlays (README.md).
CARRIER_ENV_DTBFILE=\"$DTB\""
fi

cat >"$SLOT/carrier.env" <<EOF
# Generated by scripts/build-carrier-bsp.sh from upstream.env. Do not edit.
# Consumed by stone-provision-tegraflash.sh: CARRIER_FV_* rewrite flashvars,
# CARRIER_ENV_* rewrite .env.initrd-flash.
CARRIER_LABEL="ARK Just A Jetson + Jetson Orin NX 16GB (P3767-0000), bsp-ark-jaj"

$DTB_ENV

# Bootloader configuration: ARK's MB1 pinmux/GPIO (IMU spi3, UART-A flow
# control, ...) and MB2 misc with the carrier EEPROM read disabled.
CARRIER_FV_PINMUX_CONFIG="$PINMUX"
CARRIER_FV_MB2BCT_CFG="$MB2"

# UEFI defaults: ARK's boot order (NVMe before USB, new devices such as PXE/HTTP
# boot options at the bottom), appended so it wins over the stock
# L4TConfiguration.
CARRIER_FV_BOOTCONTROL_OVERLAYS="$STOCK_OVERLAYS,ark-jaj-boot-order.dtbo"

# Refuse to flash any other module (tegraflash compares these to the EEPROM):
# this carrier's flash settings are the 16GB module's.
CARRIER_FV_CHECK_BOARDID="3767"
CARRIER_FV_CHECK_BOARDSKU="0000"
EOF

# Every file carrier.env names must exist in the merged BSP.
while IFS= read -r file; do
	[ -f "$SLOT/$file" ] || [ -f "$BSP/$file" ] || die "carrier.env references $file, which neither the slot nor the stock BSP has"
done < <(sed -n 's/^CARRIER_[A-Z_]*="\(.*\)"$/\1/p' "$SLOT/carrier.env" | tr ',' '\n' | grep -E '\.(dtbo?|dtsi?|bin)$')
if $HOOK_DELIVERS; then
	info "built stone/carrier-bsp (DTB left to Avocado's overlay hook; ${#OVERLAYS[@]} overlays checked)"
else
	info "built stone/carrier-bsp ($DTB from ${#OVERLAYS[@]} overlays)"
fi

# ---------------------------------------------------------------------------
# Install, or compare
# ---------------------------------------------------------------------------
normalize() {
	case "$1" in
	*.dtb | *.dtbo) dtc -q -I dtb -O dts -s "$1" ;;
	*) cat "$1" ;;
	esac
}
# compare <generated dir> <committed dir> <label> [file glob to limit the committed side]
compare() {
	local gen=$1 com=$2 label=$3 failed=0
	diff <(cd "$gen" && find . -type f | sort) <(cd "$com" && find . -type f ${4:+-name "$4"} | sort) \
		|| die "$label has a different file set than the pinned inputs produce"
	while IFS= read -r f; do
		# DTBs are compared decompiled: different dtc versions may order the
		# blob differently for the same tree.
		if ! diff -q <(normalize "$gen/$f") <(normalize "$com/$f") >/dev/null; then
			echo "build-carrier-bsp: differs: $label/${f#./}" >&2
			failed=1
		fi
	done < <(cd "$gen" && find . -type f | sort)
	[ "$failed" -eq 0 ] || die "$label is out of date; run scripts/build-carrier-bsp.sh and commit the result"
}

DERIVED=(jaj-hdmi-dcb.dtsi jaj-imx219-dual.dtso tegra234-camera-rbpcv2-imx219.dtsi)
if [ "$MODE" = check ]; then
	[ -d "$ROOT/stone" ] || die "stone/ is missing; run scripts/build-carrier-bsp.sh"
	compare "$WORK/stone" "$ROOT/stone" stone
	for f in "${DERIVED[@]}"; do
		cmp -s "$OVL_OUT/$f" "$ROOT/overlays/$f" || die "overlays/$f is out of date; run scripts/build-carrier-bsp.sh and commit the result"
	done
	info "stone/ and the derived overlays match upstream.env"
	exit 0
fi

rm -rf "$ROOT/stone"
cp -R "$WORK/stone" "$ROOT/stone"
for f in "${DERIVED[@]}"; do cp "$OVL_OUT/$f" "$ROOT/overlays/$f"; done
info "wrote stone/ and overlays/ from Avocado $AVOCADO_RELEASE/$AVOCADO_CHANNEL snapshot $AVOCADO_SNAPSHOT and ARK ${ARK_COMMIT:0:7}"
