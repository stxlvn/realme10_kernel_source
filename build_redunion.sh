#!/bin/bash
# RedUnion kernel build script for realme 10 (RMX3630, MT6789).
#
# Usage:
#   ./build_redunion.sh [--kpm SUPERKEY] [--jobs N]
#
# Requirements:
#   - clang/lld/llvm-* available (see TOOLCHAIN_BIN below; this repo does not
#     vendor a toolchain). Recommended: Neutron Clang
#     (https://github.com/Neutron-Toolchains/clang-build-catalogue) --
#     self-contained (bundles its own lld/llvm-ar/nm/objcopy/objdump/
#     readelf/strip and up-to-date binutils sources), built for kernel
#     cross-compilation, and noticeably faster to compile with than a
#     stock distro clang. It does NOT ship llvm-ranlib/llvm-cov/
#     llvm-addr2line -- symlink those from your distro's LLVM install
#     (version mismatch is fine, they're rarely invoked). Any clang-21+
#     works too if you'd rather not use Neutron.
#   - binutils-aarch64-linux-gnu (for aarch64-linux-gnu-elfedit et al., used
#     by the top-level Makefile to derive --target/--prefix for clang)
#   - VENDOR_ROOT pointing at a sibling checkout of
#     realme-kernel-opensource/realme10-AndroidU-vendor-source (resolves the
#     drivers/soc/oplus/*, kernel/oplus_cpu, etc. relative symlinks this tree
#     ships with)
#   - kptools-linux + kpimg (SukiSU_KernelPatch_patch release) if using --kpm
#
# Produces:
#   out/arch/arm64/boot/Image(.gz)              -- always
#   out/Image_kpm                                -- only with --kpm
#
# Does NOT produce a flashable AnyKernel3 zip -- pass out/arch/arm64/boot/Image.gz
# (or out/Image_kpm, gzipped) into your own anykernel.sh tree's Image.gz slot.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out}"
TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-$REPO_ROOT/../toolchain_bin}"
VENDOR_ROOT="${VENDOR_ROOT:-$REPO_ROOT/../vendor}"
JOBS="$(nproc)"
KPM_SUPERKEY=""
KPM_TOOLS_DIR="${KPM_TOOLS_DIR:-$REPO_ROOT/../kpm_tools}"

while [ $# -gt 0 ]; do
	case "$1" in
	--kpm)
		KPM_SUPERKEY="$2"
		shift 2
		;;
	--jobs)
		JOBS="$2"
		shift 2
		;;
	*)
		echo "Unknown argument: $1" >&2
		exit 1
		;;
	esac
done

if [ ! -x "$TOOLCHAIN_BIN/clang" ]; then
	echo "clang not found at $TOOLCHAIN_BIN/clang -- set TOOLCHAIN_BIN or symlink clang/ld.lld/llvm-* there." >&2
	exit 1
fi
if [ ! -e "$VENDOR_ROOT" ]; then
	echo "vendor tree not found at $VENDOR_ROOT -- checkout realme10-AndroidU-vendor-source as a sibling and set VENDOR_ROOT, or the drivers/soc/oplus/* symlinks in this tree won't resolve." >&2
	exit 1
fi
if ! command -v aarch64-linux-gnu-elfedit >/dev/null 2>&1; then
	echo "aarch64-linux-gnu-elfedit not found -- install binutils-aarch64-linux-gnu." >&2
	exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 not found." >&2
	exit 1
fi

export PATH="$TOOLCHAIN_BIN:$PATH"

# Re-point the vendor symlink one level up from this repo (drivers/soc/oplus/storage
# and friends resolve ../../../../vendor/... relative to the repo root's parent dir).
ln -sfn "$VENDOR_ROOT" "$REPO_ROOT/../vendor"

BUILD_DATE="$(date +%Y%m%d)"

cd "$REPO_ROOT"

make ARCH=arm64 O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 \
	CROSS_COMPILE=aarch64-linux-gnu- PYTHON=python3 \
	gki_defconfig

make ARCH=arm64 O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 \
	CROSS_COMPILE=aarch64-linux-gnu- PYTHON=python3 \
	LOCALVERSION="-nightly.$BUILD_DATE" \
	-j"$JOBS"

echo "Kernel Image: $OUT_DIR/arch/arm64/boot/Image.gz"

if [ -n "$KPM_SUPERKEY" ]; then
	if [ ! -x "$KPM_TOOLS_DIR/kptools-linux" ] || [ ! -f "$KPM_TOOLS_DIR/kpimg" ]; then
		echo "KPM requested but kptools-linux/kpimg not found in $KPM_TOOLS_DIR" >&2
		exit 1
	fi
	gunzip -c "$OUT_DIR/arch/arm64/boot/Image.gz" >"$OUT_DIR/Image_raw"
	"$KPM_TOOLS_DIR/kptools-linux" -p \
		-i "$OUT_DIR/Image_raw" \
		-k "$KPM_TOOLS_DIR/kpimg" \
		-s "$KPM_SUPERKEY" \
		-o "$OUT_DIR/Image_kpm"
	echo "KPM-patched Image: $OUT_DIR/Image_kpm (gzip it before dropping into an AnyKernel3 zip)"
fi

echo "Done."
