# Changelog

All notable changes to bsp-ark-jaj are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
