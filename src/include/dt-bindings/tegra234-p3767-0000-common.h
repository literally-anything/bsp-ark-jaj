/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Stand-in for NVIDIA's dt-bindings/tegra234-p3767-0000-common.h, which ARK's
 * camera overlay includes. That header isn't part of this repo's vendored
 * sources, and the overlay only uses this one macro from it.
 *
 * The list is the `compatible` of the stock tegra234-p3767-camera-p3768-*.dtbo
 * in Avocado's jetson-orin-nx flash BSP: every Orin NX/Nano SKU on the P3768
 * reference carrier, including the Super variants.
 */
#ifndef BSP_ARK_JAJ_TEGRA234_P3767_0000_COMMON_H
#define BSP_ARK_JAJ_TEGRA234_P3767_0000_COMMON_H

#define JETSON_COMPATIBLE_P3768 \
	"nvidia,p3768-0000+p3767-0000", "nvidia,p3768-0000+p3767-0001", \
	"nvidia,p3768-0000+p3767-0003", "nvidia,p3768-0000+p3767-0004", \
	"nvidia,p3768-0000+p3767-0005", "nvidia,p3768-0000+p3767-0000-super", \
	"nvidia,p3768-0000+p3767-0001-super", "nvidia,p3768-0000+p3767-0003-super", \
	"nvidia,p3768-0000+p3767-0004-super", "nvidia,p3768-0000+p3767-0005-super"

#endif
