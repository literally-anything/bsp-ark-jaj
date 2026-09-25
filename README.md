# bsp-ark-jaj

[Avocado OS](https://avocadolinux.org) board support for the
[ARK Electronics Just A Jetson](https://docs.arkelectron.com/products/embedded-computers/ark-just-a-jetson)
(JAJ) carrier with an NVIDIA **Jetson Orin NX 16GB** (P3767-0000).

It works like Avocado's own carrier boards (for example the Advantech ICAM-540):
the extension `avocado-bsp-ark-jaj` is a **carrier extension on the generic
`jetson-orin-nx` target**. It replaces `avocado-bsp-jetson-orin-nx`; don't use
both.

**16GB only.** That's the `jetson-orin-nx` target's default module, so the flash
BSP's memory, power-management and nvpmodel settings already match. Other
modules would need their own flash settings (see "Other modules" below). The
tegraflash SKU check refuses to flash any other module.

Built and tested against Avocado 2024/edge (jetson-orin-nx snapshot 17, kernel
6.6.127, L4T 36.5) with avocado-cli 1.0.0-rc.5.

## Using it

Declare it with a **git source pinned to a release tag**, and select it with the
board variant:

```yaml
supported_targets:
  - jetson-orin-nx

runtimes:
  dev:
    targets: [jetson-orin-nx]           # plus any others the runtime covers
    extensions:
      - avocado-bsp-{{ avocado.target.board }}
      # ...

extensions:
  avocado-bsp-ark-jaj:
    source: { type: git, url: https://github.com/literally-anything/bsp-ark-jaj, ref: '0.2.0' }
```

```sh
avocado install -r dev --target jetson-orin-nx --target-board ark-jaj
avocado build   -r dev --target jetson-orin-nx --target-board ark-jaj
avocado provision dev --target jetson-orin-nx --target-board ark-jaj
```

- **Tags only for `ref`.** avocado-cli 1.0.0-rc.5 clones with `git clone --branch <ref>`. For a commit hash that fails, it falls back to the default branch, and the checkout of the hash fails silently, so you build the branch tip. The lock file doesn't record the commit either.
- **`--target-board` is needed.** Without it the board defaults to the target name, which selects Avocado's `avocado-bsp-jetson-orin-nx`. `AVOCADO_TARGET_BOARD` works too.

### Only one `carrier-bsp/` is used

The flash takes the whole `carrier-bsp/` folder from the first include path
that has one. To add project flash settings (extra UEFI defaults, for
example), merge this board's `stone/carrier-bsp/` into your own copy and list
that on a runtime-level `stone_include_paths` entry, which is searched before
extensions.

## What's in it

### Device tree: overlays

The JAJ's kernel device tree is Avocado's stock
`tegra234-p3768-0000+p3767-0000-nv-super.dtb` plus these overlays, applied in
order. They're listed under `x-device-tree-overlays` in `avocado.yaml`, in exactly
the shape of an extension's `device_tree_overlays`:

| Overlay | What it does |
|---|---|
| `overlays/jaj-lane-labels.dtso` | Labels the XUSB pad lanes. The stock tree gives them none, and an overlay can only reference base nodes by label |
| `overlays/jaj-carrier.dtso` | ARK's carrier changes, ported from `src/ark/ark-JAJ-overrides.dtsi`: USB-C device controller on the `usb3-0` lane, third USB 3 lane for the dual USB-A port, UART-B (`/dev/ttyTHS3`), UART-A in PIO mode, HD audio, HDMI display control block, active-low hotplug, FFC PCIe capped at Gen2, and the model string |
| `overlays/jaj-imx219-dual.dtso` | ARK's dual IMX219 camera overlay |

Two of ARK's changes delete properties, which an overlay can't do:

- **UART-A DMA:** ARK deletes `dmas`/`dma-names` because the stock DMA path corrupts RX at 3 Mbaud. Here `dma-names` is overwritten instead. The 6.6 `serial-tegra` driver takes PIO mode for any direction with no `"rx"`/`"tx"` entry, which is the same end state.
- **`hdcp_enabled`:** not carried over. ARK removes it only to avoid a DP-to-HDMI adapter regression, and notes that native HDMI (the JAJ's) shouldn't hit it.

Avocado's `device_tree_overlays` support isn't usable on Jetson yet. The Tegra
merge hook was merged in meta-avocado #292, but its packages
(`avocado-dtc-overlay-deliver`, `nativesdk-avocado-dtc-overlay`) aren't in any
feed, and declaring overlays makes `sdk install` fail. Until then,
`scripts/build-carrier-bsp.sh` does what the hook will do:

1. Compile each overlay like `avocado-dtc-overlay`.
2. Merge them all into the stock DTB with one `fdtoverlay` call.
3. Ship the result through `carrier-bsp/` (`CARRIER_ENV_DTBFILE`).

`scripts/check-avocado-hook.sh` runs meta-avocado's **real** compiler and Tegra
hook in the SDK and checks that they produce exactly the committed DTB. CI runs
it on every build.

#### Switching to `device_tree_overlays`

When a Jetson feed publishes the two packages:

1. In `avocado.yaml`, uncomment `device_tree_overlays: *jaj_overlays` on the extension.
2. Run `scripts/in-container.sh scripts/build-carrier-bsp.sh`. When it sees that line, it stops shipping its own DTB and the `CARRIER_ENV_DTBFILE` line, but still builds the DTB to run its checks.
3. Bump the version and tag.

What gets flashed doesn't change; `check-avocado-hook.sh` is the proof. The hook
publishes the merged tree under the stock DTB name, which the flash already
uses.

### Flash files: `stone/carrier-bsp/`

Generated by `scripts/build-carrier-bsp.sh` from the pinned inputs in
`upstream.env`. Nothing here is hand-edited.

| File | What it is |
|---|---|
| `tegra234-p3768-0000+p3767-0000-nv-super-ark-jaj.dtb` | The kernel DTB above |
| `tegra234-mb1-bct-pinmux-…-ark-jaj.dtsi`, `…-gpio-…-ark-jaj.dtsi` | ARK's MB1 pinmux/GPIO: IMU on spi3 and UART-A RTS/CTS at power-on, I2S0 pins safe from power-on |
| `tegra234-mb2-bct-misc-p3767-0000-ark-jaj.dts` | Stock MB2 misc with `cvb_eeprom_read_size = 0` (ARK's only change to it) |
| `ark-jaj-boot-order.dtbo` | ARK's UEFI overlay: NVMe before USB, new devices (PXE/HTTP boot options) at the bottom |
| `carrier.env` | Points the flash at the files above, and pins the SKU check to the 16GB module |

Not carried over from ARK: their pad-voltage file, which is identical to stock
apart from comments, and their Orin Nano C7 link-rate patch, which only applies
to Nano modules.

### On the device

- **Orin NX module:** the same drivers and L4T userspace as `avocado-bsp-jetson-orin-nx` 0.1.0.
- **CAN:** `mttcan` for the onboard transceiver (`can0`).
- **CSI cameras:** NVIDIA's capture stack and the IMX219 driver.
- **M.2 Key E:** Intel AX200/AX210 WiFi and Bluetooth.
- **Ethernet:** `r8169` firmware (`linux-firmware-rtl8168`).

## Update paths

What an update can change on the Orin NX today (Avocado 2024, meta-avocado's
[`stone-jetson-orin-nx.json`](https://github.com/avocado-linux/meta-avocado/blob/16e632832b3ee10e72c3c2f194e847f8098603c9/meta-avocado-nvidia/stone/stone-jetson-orin-nx.json)
lists only `rootfs` under `os_artifacts`):

| Part | Where it lives | Changes by |
|---|---|---|
| Drivers, firmware, L4T userspace | this extension (sysext/confext) | runtime update or `avocado deploy` |
| Kernel device tree (`overlays/`) | `A_kernel-dtb` / `B_kernel-dtb` | **reflash only** |
| Bootloader configuration (pinmux/GPIO, MB2) | QSPI A/B boot chain | **reflash only** |
| UEFI defaults (`ark-jaj-boot-order.dtbo`) | UEFI, applied at flash | **reflash only**. `NewDeviceHierarchy` can also be changed later from the UEFI menu or efivars; `DefaultBootPriority` is locked |
| Kernel | `A_kernel` / `B_kernel` | **reflash only** (Avocado made it OTA-updatable for AGX Thor only, meta-avocado #350) |

The repo is laid out so each of those can move to OTA without restructuring,
once Avocado supports it:

- **Kernel DTB:** it's already the output of Avocado's own overlay tooling (see above). A `kernel_dtb` OS artifact targeting `A_kernel-dtb`/`B_kernel-dtb` would carry exactly this tree.
- **Bootloader and UEFI defaults:** they're self-contained in `carrier-bsp/` as the standard `CARRIER_FV_*` retargets. A UEFI capsule built from the same patched flashvars would carry them.

## Other modules

A different module (Orin NX 8GB, or an Orin Nano) needs different flash
settings (DTB, BPMP DTB, SDRAM configuration, chip SKU, SKU check) and a
different nvpmodel table. Avocado has no provision-time SKU detection, so that
means another carrier extension. Version 0.1.0 of this repo had an 8GB variant
(`avocado-bsp-ark-jaj-nx8`), and its `carrier.env` values are in the git
history.

## Updating

- **New Avocado snapshot:** the weekly `drift` CI job fails when the feed's
  newest `jetson-orin-nx` snapshot ships a different flash BSP. Then:
  1. Update `AVOCADO_SNAPSHOT` and `BOOTFILES_SHA256` in `upstream.env` to the values in the failure message.
  2. Run `scripts/in-container.sh scripts/build-carrier-bsp.sh`.
  3. Review the DTB diff (`dtc -I dtb -O dts`), then commit and tag.
- **New ARK release:** set `ARK_COMMIT` and run `scripts/update-sources.sh`. If
  `src/ark/ark-JAJ-overrides.dtsi` changed, port the change to
  `overlays/jaj-carrier.dtso`. Then regenerate as above.

`build-carrier-bsp.sh` only runs with **dtc 1.7.x**, the Avocado 2024 SDK's
version. dtc versions differ in how `fdtoverlay` numbers phandles on labelled
overlay nodes, so another version builds an equivalent but different DTB.
`scripts/in-container.sh` runs it in Ubuntu 24.04 (dtc 1.7.0), through the
avocado-vm's Docker on macOS. CI pins `ubuntu-24.04` for the same reason.

CI (`.github/workflows/ci.yml`):

- regenerates everything and fails if `stone/` or the derived overlay files differ
- builds the extension with the Avocado CLI
- runs `check-avocado-hook.sh`
- on tags, checks that the tag equals the extension's `version`

## First boot on a JAJ

Flash with the serial console attached (`ttyTCU0`, the UART2 connector), then check:

- **USB-C gadget:** `/sys/class/udc/3550000.usb/state` reaches `configured`.
- **Ethernet:** find its path with `udevadm info -q property -p /sys/class/net/eth0 | grep ID_PATH`. It should be on PCIe C8 (`platform-140a0000.pcie-pci-0008:01:00.0`), as on the devkit.
- **CAN:** `can0` exists.
- **Cameras:** `/dev/video0` and `/dev/video1` exist.
- **IMU and INA238:** `/dev/spidev1.0` exists and `i2cdetect -y -r 7` shows `0x45`.
- **UART-A:** in PIO mode (`dmesg | grep "PIO mode"`), and clean at 3 Mbaud.
- **HDMI:** output works.
- **Model:** `cat /proc/device-tree/model` names the JAJ.

## JAJ hardware on Avocado

| | Linux |
|---|---|
| Console (UART2 connector) | `ttyTCU0`, 115200. Same combined UART as the devkit |
| UART1 / UART0 connectors | `/dev/ttyTHS1` / `/dev/ttyTHS3` |
| IMU (ICM-42688P, SPI1) | `/dev/spidev1.0` (spi@3230000 CS0). No kernel IIO driver in the feed; use it from userspace like ARK's `icm42688p_test.py` |
| Carrier power monitor (INA238) | `/dev/i2c-7`, address `0x45`. No hwmon driver in the feed; read it over I2C like ARK's `ina238_test.py` |
| Module power monitor (INA3221) | hwmon (`ina3221` driver) |
| CAN | `can0` |
| USB-C | Host or device. `tegra-xudc` gadget on `3550000.usb` |

## License

GPL-2.0-only (`LICENSE`), because the DTB is built from GPL-2.0 device-tree
sources. Vendored files keep their own headers:

- ARK's device-tree fragment and overlays, and NVIDIA's HDMI display data: GPL-2.0
- NVIDIA's pinmux/GPIO BCT files: BSD-3-Clause
- Linux dt-bindings headers: GPL-2.0 OR MIT

Upstream sources are ARK Electronics'
[ark_jetson_kernel](https://github.com/ARK-Electronics/ark_jetson_kernel) (commit in
`upstream.env`) and Avocado's `avocado-img-bootfiles` for `jetson-orin-nx`.
