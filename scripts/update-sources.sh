#!/usr/bin/env bash
# Re-vendors the upstream sources pinned in upstream.env:
#   src/ark/      ARK's JAJ carrier files, byte-for-byte from ARK_COMMIT
#   src/include/  dt-bindings headers from LINUX_TAG
#
# Files are copied unmodified (ARK's BCT dtsi stay CRLF). Anything JAJ-specific
# that this repo changes happens in scripts/build-carrier-bsp.sh, never here, so
# a re-vendor never silently drops a local edit.
#
# Usage: scripts/update-sources.sh [path-to-ark_jetson_kernel-checkout]
set -euo pipefail

cd "$(dirname "$0")/.."
. ./upstream.env

die() {
	echo "update-sources: $*" >&2
	exit 1
}

for tool in git curl; do
	command -v "$tool" >/dev/null || die "$tool not found"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ $# -ge 1 ]; then
	ark="$1"
else
	ark="$tmp/ark"
	git clone -q --filter=blob:none --no-checkout "$ARK_REPO" "$ark"
fi
git -C "$ark" cat-file -e "$ARK_COMMIT^{commit}" 2>/dev/null \
	|| git -C "$ark" fetch -q origin "$ARK_COMMIT" \
	|| die "commit $ARK_COMMIT not found in $ARK_REPO"

# destination -> path in ARK's repo
ark_files=(
	"ark-JAJ-overrides.dtsi=products/JAJ/device_tree/source/hardware/nvidia/t23x/nv-public/nv-platform/ark-JAJ-overrides.dtsi"
	"tegra234-dcb-p3737-0000-p3701-0000-hdmi.dtsi=products/JAJ/device_tree/source/hardware/nvidia/t23x/nv-public/nv-platform/tegra234-dcb-p3737-0000-p3701-0000-hdmi.dtsi"
	"tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi=products/JAJ/device_tree/bootloader/generic/BCT/tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi"
	"tegra234-mb1-bct-gpio-p3767-dp-a03.dtsi=products/JAJ/device_tree/bootloader/tegra234-mb1-bct-gpio-p3767-dp-a03.dtsi"
	"tegra234-p3767-camera-p3768-imx219-dual.dts=products/JAJ/overlay/tegra234-p3767-camera-p3768-imx219-dual.dts"
	"tegra234-camera-rbpcv2-imx219.dtsi=products/JAJ/overlay/tegra234-camera-rbpcv2-imx219.dtsi"
	"ark_boot_order.dts=products/JAJ/overlay/ark_boot_order.dts"
	"dtb_models.env=products/JAJ/dtb_models.env"
)

rm -rf src/ark
mkdir -p src/ark
for entry in "${ark_files[@]}"; do
	dest="${entry%%=*}"
	path="${entry#*=}"
	git -C "$ark" show "$ARK_COMMIT:$path" >"src/ark/$dest" || die "$path missing at $ARK_COMMIT"
done

linux_headers=(
	clock/tegra234-clock.h
	reset/tegra234-reset.h
	gpio/gpio.h
	gpio/tegra234-gpio.h
	interrupt-controller/arm-gic.h
	interrupt-controller/irq.h
)
for h in "${linux_headers[@]}"; do
	mkdir -p "src/include/dt-bindings/$(dirname "$h")"
	curl -fsSL "$LINUX_REPO/$LINUX_TAG/include/dt-bindings/$h" -o "src/include/dt-bindings/$h" \
		|| die "dt-bindings/$h not found at $LINUX_TAG"
done

echo "update-sources: vendored ARK $ARK_COMMIT and Linux $LINUX_TAG headers"
echo "update-sources: now run scripts/build-carrier-bsp.sh and review the diff"
