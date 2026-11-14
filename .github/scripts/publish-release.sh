#!/usr/bin/env bash
# Verify a draft release created by build-armbian.yml and publish it.
#
# Shared by publish-release.yml (manual) and build-armbian.yml (scheduled run),
# so the guards only exist in one place. Everything runs under `set -e`; any
# failed guard exits non-zero *before* the release is touched, leaving it as a
# draft.
#
# Environment:
#   REPO          owner/repo (required)
#   TAG           tag of the existing draft release (required)
#   PRERELEASE    "true" to publish as pre-release, anything else = false
#   GH_TOKEN      token with contents: write (required by gh)

set -euo pipefail

: "${REPO:?REPO is required}"
: "${TAG:?TAG is required}"
PRERELEASE="${PRERELEASE:-false}"

CHECK_DIR="$(mktemp -d)"

show_release() {
	echo "  tag:         ${TAG}"
	echo "  release id:  ${RELEASE_ID:-<unknown>}"
	echo "  draft:       ${IS_DRAFT:-<unknown>}"
	echo "  assets:      ${ASSET_COUNT:-<unknown>}"
	echo "  image files: ${IMAGE_COUNT:-<unknown>} (*.img.xz, includes *.burn.img.xz)"
	echo "  asset list:"
	echo "${MATCHES:-[]}" | jq -r '.[0].assets[]? | "    \(.name)  [\(.size) bytes, \(.state)]"'
}

fail() {
	echo "ERROR: $*" >&2
	echo "---- release state at failure ----" >&2
	show_release >&2 || true
	exit 1
}

load_release() {
	local all
	# Draft releases are not returned by /releases/tags/{tag}, so look the tag
	# up in the full release list instead.
	all="$(gh api --paginate "repos/${REPO}/releases?per_page=100" | jq -s 'add // []')"
	MATCHES="$(echo "${all}" | jq --arg t "${TAG}" '[.[] | select(.tag_name == $t)]')"
}

if [ -z "${TAG}" ]; then
	fail "tag is empty"
fi
echo "Publishing tag: ${TAG} in ${REPO}"

load_release
MATCH_COUNT="$(echo "${MATCHES}" | jq 'length')"
if [ "${MATCH_COUNT}" -ne 1 ]; then
	fail "expected exactly 1 release with tag '${TAG}', found ${MATCH_COUNT}"
fi

RELEASE_ID="$(echo "${MATCHES}" | jq -r '.[0].id')"
IS_DRAFT="$(echo "${MATCHES}" | jq -r '.[0].draft')"
ASSET_COUNT="$(echo "${MATCHES}" | jq -r '.[0].assets | length')"
IMAGE_COUNT="$(echo "${MATCHES}" | jq -r '[.[0].assets[] | select(.name | endswith(".img.xz"))] | length')"
ASSET_NAMES="$(echo "${MATCHES}" | jq -r '.[0].assets[].name')"

echo "---- release state before publish ----"
show_release

# Guard 2: must still be a draft.
if [ "${IS_DRAFT}" != "true" ]; then
	fail "release '${TAG}' is not a draft (draft=${IS_DRAFT}); refusing to publish"
fi

# Guard 3: must have assets.
if [ "${ASSET_COUNT}" -le 0 ]; then
	fail "release '${TAG}' has no assets"
fi

# Guard 4: sha256sums.txt must exist.
SUMS_ID="$(echo "${MATCHES}" | jq -r '.[0].assets[] | select(.name == "sha256sums.txt") | .id' | head -1)"
if [ -z "${SUMS_ID}" ] || [ "${SUMS_ID}" = "null" ]; then
	fail "release '${TAG}' has no sha256sums.txt asset"
fi

gh api "repos/${REPO}/releases/assets/${SUMS_ID}" \
	-H "Accept: application/octet-stream" > "${CHECK_DIR}/sha256sums.txt"

# Guard 5: checksum line count must match the number of image files.
SUMS_LINES="$(grep -cve '^[[:space:]]*$' "${CHECK_DIR}/sha256sums.txt" || true)"
if [ "${SUMS_LINES}" -ne "${IMAGE_COUNT}" ]; then
	fail "sha256sums.txt has ${SUMS_LINES} line(s) but the release has ${IMAGE_COUNT} image file(s)"
fi

# Guard 6: every name listed in sha256sums.txt must be an asset of this release.
while read -r sum_name; do
	[ -z "${sum_name}" ] && continue
	if ! echo "${ASSET_NAMES}" | grep -qxF "${sum_name}"; then
		fail "sha256sums.txt lists '${sum_name}' which is not an asset of this release"
	fi
done < <(awk '{print $2}' "${CHECK_DIR}/sha256sums.txt")

echo "Checks passed: draft=${IS_DRAFT}, assets=${ASSET_COUNT}, images=${IMAGE_COUNT}, sha256sums.txt=${SUMS_LINES} line(s)"

PRERELEASE_FLAG="--prerelease=false"
if [ "${PRERELEASE}" = "true" ]; then
	PRERELEASE_FLAG="--prerelease=true"
fi

echo "Publishing release '${TAG}' (draft=false, ${PRERELEASE_FLAG})"
gh release edit "${TAG}" --repo "${REPO}" --draft=false "${PRERELEASE_FLAG}"

# Guard 7: the release must really be published now.
load_release
IS_DRAFT="$(echo "${MATCHES}" | jq -r '.[0].draft')"
ASSET_COUNT="$(echo "${MATCHES}" | jq -r '.[0].assets | length')"
IMAGE_COUNT="$(echo "${MATCHES}" | jq -r '[.[0].assets[] | select(.name | endswith(".img.xz"))] | length')"

echo "---- release state after publish ----"
show_release

if [ "${IS_DRAFT}" != "false" ]; then
	fail "release '${TAG}' is still draft after publish"
fi
echo "OK: '${TAG}' is published with ${ASSET_COUNT} asset(s), ${IMAGE_COUNT} image file(s)."
