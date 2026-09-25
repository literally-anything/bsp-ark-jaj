#!/usr/bin/env bash
# sdk.compile step: fetches NVIDIA's nvpmodel power-mode tables for the Orin NX
# modules into $AVOCADO_BUILD_DIR.
#
# The jetson-orin-nx image bakes the 16GB module's table into /etc/nvpmodel.conf.
# The 8GB module has 6 CPU cores instead of 8 and a smaller GPU, so its table
# differs, and nothing in the feed ships it. These files carry NVIDIA's license,
# so they're downloaded at build time (as meta-tegra does) instead of being
# committed here. The pin lives in this script so changing it triggers a rebuild.
set -euo pipefail

DEB_URL=https://repo.download.nvidia.com/jetson/t234/pool/main/n/nvidia-l4t-nvpmodel/nvidia-l4t-nvpmodel_36.5.0-20260115194252_arm64.deb
DEB_SHA256=bce27effb467c9b9f5c59c6700c2f131e556a7004628190438229bb994d74eb9
CONFS=(nvpmodel_p3767_0000_super.conf nvpmodel_p3767_0001_super.conf)

die() {
	echo "fetch-nvpmodel: $*" >&2
	exit 1
}

[ -n "${AVOCADO_BUILD_DIR:-}" ] || die "AVOCADO_BUILD_DIR is not set"
for tool in curl zstd tar python3 sha256sum; do
	command -v "$tool" >/dev/null || die "$tool not found in the SDK; add avocado-sdk-toolchain to your project's sdk.packages"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$DEB_URL" -o "$tmp/nvpmodel.deb" || die "download failed: $DEB_URL"
echo "$DEB_SHA256  $tmp/nvpmodel.deb" | sha256sum -c --status || die "checksum mismatch for $DEB_URL"

# A .deb is an ar archive; the SDK has no ar, so unpack data.tar.* with Python.
python3 - "$tmp/nvpmodel.deb" "$tmp" <<'EOF'
import sys
deb, out = sys.argv[1], sys.argv[2]
with open(deb, "rb") as f:
    if f.read(8) != b"!<arch>\n":
        sys.exit("not an ar archive")
    while header := f.read(60):
        name = header[:16].decode().strip().rstrip("/")
        size = int(header[48:58].decode())
        data = f.read(size)
        f.read(size % 2)
        if name.startswith("data.tar"):
            open(f"{out}/{name}", "wb").write(data)
            break
    else:
        sys.exit("no data.tar member")
EOF

data=$(ls "$tmp"/data.tar.* 2>/dev/null | head -n 1)
[ -n "$data" ] || die "no data.tar in the package"
case "$data" in
*.zst) zstd -dcq "$data" >"$tmp/data.tar" ;;
*.xz) xz -dc "$data" >"$tmp/data.tar" ;;
*) die "unexpected member $(basename "$data")" ;;
esac

mkdir -p "$AVOCADO_BUILD_DIR"
for conf in "${CONFS[@]}"; do
	tar -xOf "$tmp/data.tar" "./etc/nvpmodel/$conf" >"$AVOCADO_BUILD_DIR/$conf" || die "$conf not in the package"
	grep -q '^< POWER_MODEL ID=0 ' "$AVOCADO_BUILD_DIR/$conf" || die "$conf has no power models"
done
echo "fetch-nvpmodel: fetched ${CONFS[*]}"
