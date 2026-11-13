#!/usr/bin/env bash
# Append the HDMI variant to the image file name.
#
# The matrix builds the same release/type twice: once with the patched HDMI
# kernel and once without. Without this suffix both jobs produce identical
# file names, so artifacts and the release assets overwrite each other.
#
# HDMI_VARIANT is exported by the workflow (use_hdmi / no_hdmi).

function extension_prepare_config__hdmi_variant() {
	[[ -z "${HDMI_VARIANT:-}" ]] && return 0

	EXTRA_IMAGE_SUFFIXES+=("-${HDMI_VARIANT}")
	display_alert "HDMI variant image suffix" "-${HDMI_VARIANT}" "info"
}
