# Changelog

All notable changes to bsp-ark-jaj are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

### Changed
- **Breaking:** one extension, `avocado-bsp-ark-jaj`, for the Orin NX 16GB
  only. The board variant is now `ark-jaj`. The 8GB variant
  (`avocado-bsp-ark-jaj-nx8`) and its nvpmodel download step are removed; the
  16GB module is the target's default, so its nvpmodel table is already in the
  image.
- The kernel DTB is now built from device-tree overlays (`overlays/`, listed
  under `x-device-tree-overlays` in `avocado.yaml`), applied to the stock DTB
  exactly as Avocado's Tegra overlay hook does. Switching to
  `device_tree_overlays` once the hook is published changes nothing that gets
  flashed.
- UART-A is put in PIO mode by overwriting `dma-names` instead of deleting the
  DMA properties, and `hdcp_enabled` is no longer removed (ARK notes native HDMI
  isn't affected).
- Flash files moved to the standard `stone/carrier-bsp/`.
- `build-carrier-bsp.sh` requires dtc 1.7.x (the Avocado 2024 SDK's);
  `scripts/in-container.sh` runs it in Ubuntu 24.04.

### Added
- `scripts/check-avocado-hook.sh`: runs meta-avocado's own overlay compiler and
  Tegra merge hook in the SDK and checks they produce the committed DTB. Run in CI.
- README: which parts change only on a reflash, and how each could move to OTA.

## [0.1.0]

### Added
- `avocado-bsp-ark-jaj-nx16` and `avocado-bsp-ark-jaj-nx8`: carrier extensions
  for the ARK Just A Jetson with an Orin NX 16GB / 8GB, on the `jetson-orin-nx`
  target (Avocado 2024/edge snapshot 17, L4T 36.5).
- Flash-time carrier BSP generated from Avocado's stock DTBs and ARK's JAJ
  sources (ark_jetson_kernel 93e5e97): kernel DTB with ARK's carrier fragment
  and dual IMX219 overlay, ARK's MB1 pinmux/GPIO, MB2 misc without the carrier
  EEPROM read, ARK's UEFI boot order, per-SKU flash settings and SKU check.
- On-device support for CAN, CSI cameras (IMX219), Intel AX2xx WiFi/Bluetooth,
  Ethernet firmware, and the module's nvpmodel power table.
- CI: generated files match the pins, both extensions build, weekly feed drift
  check.
