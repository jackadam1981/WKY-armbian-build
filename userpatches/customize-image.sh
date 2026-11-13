#!/bin/bash
#
# Armbian image customization hook for OneCloud (meson8b).
#
# Why this exists:
#   The OneCloud boot script hardcodes the device tree path:
#     fatload ${bootdev} 0x21800000 /dtb/meson8b-onecloud.dtb || exit 1
#   and the only component that populates /boot/dtb on a FAT /boot is the
#   linux-dtb package postinst (which moves /boot/dtb-<ver> to /boot/dtb).
#   If that postinst does not run (or fails), the board cannot boot at all.
#
#   This hook makes the DTB presence deterministic at image build time by
#   copying the DTB tree of the installed kernel from the linux-image package
#   payload (/usr/lib/linux-image-*) to /boot/dtb, independent of linux-dtb.
#
# Invocation (by Armbian, inside the target chroot):
#   customize-image.sh "${RELEASE}" "${LINUXFAMILY}" "${BOARD}" "${BUILD_DESKTOP}" "${ARCH}"
#
# This runs during the rootfs customization stage, after kernel packages are
# installed and before /boot is packed into the FAT partition / boot.scr is
# compiled, so writing to /boot here lands in the final boot partition.

set -u

RELEASE="${1:-}"
LINUXFAMILY="${2:-}"
BOARD="${3:-}"
BUILD_DESKTOP="${4:-}"
ARCH="${5:-}"

DTB_NAME="meson8b-onecloud.dtb"
TARGET_DIR="/boot/dtb"

fail() {
	echo "ERROR: [customize-image] $*" >&2
	exit 1
}

log() {
	echo "[customize-image] $*"
}

log "RELEASE=${RELEASE} LINUXFAMILY=${LINUXFAMILY} BOARD=${BOARD} BUILD_DESKTOP=${BUILD_DESKTOP} ARCH=${ARCH}"

# Only onecloud has the FAT /boot + fixed /dtb/<file> boot script combination.
if [ "${BOARD}" != "onecloud" ]; then
	log "BOARD is not onecloud, skipping DTB fallback copy."
	exit 0
fi

# ---------------------------------------------------------------------------
# 1. Locate the kernel DTB tree shipped by linux-image. Exactly one installed
#    kernel is expected in a fresh image; anything else is an error, because
#    silently picking a stale directory could ship the wrong DTB.
# ---------------------------------------------------------------------------
shopt -s nullglob
dtb_dirs=(/usr/lib/linux-image-*)
shopt -u nullglob

if [ "${#dtb_dirs[@]}" -ne 1 ]; then
	fail "expected exactly one /usr/lib/linux-image-* directory, found ${#dtb_dirs[@]}: ${dtb_dirs[*]:-none}"
fi

DTB_SRC_DIR="${dtb_dirs[0]}"
[ -d "${DTB_SRC_DIR}" ] || fail "DTB source directory does not exist: ${DTB_SRC_DIR}"
log "DTB source directory: ${DTB_SRC_DIR}"

# ---------------------------------------------------------------------------
# 2. Cross-check the directory against the installed linux-image package, so a
#    leftover directory from an older kernel can never be selected.
# ---------------------------------------------------------------------------
kernel_pkgs=$(dpkg-query -W -f='${Package}\n' "linux-image-*-${LINUXFAMILY}" 2>/dev/null || true)
kernel_pkg_count=$(printf '%s\n' "${kernel_pkgs}" | grep -c . || true)

if [ "${kernel_pkg_count}" -ne 1 ]; then
	fail "expected exactly one installed linux-image-*-${LINUXFAMILY} package, found ${kernel_pkg_count}: ${kernel_pkgs:-none}"
fi

KERNEL_PKG="${kernel_pkgs}"
KERNEL_PKG_VERSION=$(dpkg-query -W -f='${Version}' "${KERNEL_PKG}") || fail "cannot query version of ${KERNEL_PKG}"
log "Kernel package: ${KERNEL_PKG} version ${KERNEL_PKG_VERSION}"

pkg_dtb_dir=$(dpkg-query -L "${KERNEL_PKG}" 2>/dev/null | grep '^/usr/lib/linux-image-' | head -1 | cut -d/ -f1-4)

if [ -z "${pkg_dtb_dir}" ]; then
	fail "${KERNEL_PKG} does not ship any /usr/lib/linux-image-* files"
fi

if [ "${pkg_dtb_dir}" != "${DTB_SRC_DIR}" ]; then
	fail "DTB directory mismatch: found '${DTB_SRC_DIR}', but ${KERNEL_PKG} owns '${pkg_dtb_dir}'"
fi
log "DTB directory cross-check OK"

# ---------------------------------------------------------------------------
# 3. Find the DTB the boot script expects.
# ---------------------------------------------------------------------------
DTB_SRC_FILE=$(find "${DTB_SRC_DIR}" -type f -name "${DTB_NAME}" | head -1)
[ -n "${DTB_SRC_FILE}" ] || fail "${DTB_NAME} not found under ${DTB_SRC_DIR}"
log "DTB source file: ${DTB_SRC_FILE}"

# ---------------------------------------------------------------------------
# 4. Replace /boot/dtb with a fresh copy. FAT does not support symlinks, so
#    this must be a real copy (cp -rL dereferences any symlinks in the tree).
# ---------------------------------------------------------------------------
rm -rf "${TARGET_DIR}" || fail "cannot remove ${TARGET_DIR}"
mkdir -p "${TARGET_DIR}" || fail "cannot create ${TARGET_DIR}"

cp -rL "${DTB_SRC_DIR}/." "${TARGET_DIR}/" || fail "failed to copy DTB tree to ${TARGET_DIR}"

# The boot script uses a flat path, so make sure it exists even if the kernel
# ships this DTB inside a vendor subdirectory (e.g. amlogic/).
if [ "${DTB_SRC_FILE}" != "${DTB_SRC_DIR}/${DTB_NAME}" ]; then
	cp -fL "${DTB_SRC_FILE}" "${TARGET_DIR}/${DTB_NAME}" || fail "failed to flatten ${DTB_NAME}"
fi

chmod 644 "${TARGET_DIR}/${DTB_NAME}" || fail "cannot chmod ${TARGET_DIR}/${DTB_NAME}"

# ---------------------------------------------------------------------------
# 5. Verify: existence, size, sha256 and byte-for-byte comparison. Any failure
#    aborts the build (Armbian turns a non-zero exit into a hard build error).
# ---------------------------------------------------------------------------
TARGET_FILE="${TARGET_DIR}/${DTB_NAME}"

[ -f "${TARGET_FILE}" ] || fail "verification failed: ${TARGET_FILE} is missing"

src_size=$(stat -c '%s' "${DTB_SRC_FILE}")
dst_size=$(stat -c '%s' "${TARGET_FILE}")
[ "${src_size}" = "${dst_size}" ] || fail "verification failed: size mismatch (${src_size} != ${dst_size})"

src_sha=$(sha256sum "${DTB_SRC_FILE}" | awk '{print $1}')
dst_sha=$(sha256sum "${TARGET_FILE}" | awk '{print $1}')
[ "${src_sha}" = "${dst_sha}" ] || fail "verification failed: sha256 mismatch (${src_sha} != ${dst_sha})"

cmp -s "${DTB_SRC_FILE}" "${TARGET_FILE}" || fail "verification failed: cmp mismatch"

log "OK: ${TARGET_FILE} (${dst_size} bytes, sha256 ${dst_sha})"
exit 0
