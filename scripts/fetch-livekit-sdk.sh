#!/usr/bin/env bash
# Downloads the pinned prebuilt LiveKit C++ SDK (github.com/livekit/client-sdk-cpp,
# Apache-2.0) into unreal/Source/ThirdParty/LiveKitSDK/<Platform>/, verifying
# each archive against its pinned SHA-256. The extracted SDK is git-ignored.
#
# Usage: scripts/fetch-livekit-sdk.sh [Mac|Win64 ...]   (default: both)
set -euo pipefail

VERSION="1.12.3"
BASE_URL="https://github.com/livekit/client-sdk-cpp/releases/download/v${VERSION}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="${ROOT}/unreal/Source/ThirdParty/LiveKitSDK"

asset_for() {
  case "$1" in
    Mac) echo "livekit-sdk-macos-arm64-${VERSION}.tar.gz 5103d669fe5f13f987e21906890e7f8f96b490f9de9487621334da8d3424692e" ;;
    Win64) echo "livekit-sdk-windows-x64-${VERSION}.zip 81c39cb1469d873a657a1931ad40ead7cfc42d337d61b56de57a16beb95f8a70" ;;
    *) echo "Unknown platform: $1 (expected Mac or Win64)" >&2; return 1 ;;
  esac
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

platforms=("$@")
[ ${#platforms[@]} -eq 0 ] && platforms=(Mac Win64)

for platform in "${platforms[@]}"; do
  read -r name expected < <(asset_for "$platform")
  dest="${DEST_ROOT}/${platform}"
  if [ -f "${dest}/.version" ] && [ "$(cat "${dest}/.version")" = "${VERSION}" ]; then
    echo "LiveKit SDK ${VERSION} for ${platform} already present."
    continue
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading ${name}..."
  curl -fsSL -o "${tmp}/${name}" "${BASE_URL}/${name}"

  actual="$(sha256_of "${tmp}/${name}")"
  if [ "$actual" != "$expected" ]; then
    echo "Checksum mismatch for ${name}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi

  mkdir -p "${tmp}/extract"
  case "$name" in
    *.tar.gz) tar -xzf "${tmp}/${name}" -C "${tmp}/extract" ;;
    *.zip) unzip -q "${tmp}/${name}" -d "${tmp}/extract" ;;
  esac

  # The archive holds a single top-level folder; flatten it into ${dest}.
  shopt -s nullglob dotglob
  entries=("${tmp}/extract"/*)
  src="${tmp}/extract"
  if [ ${#entries[@]} -eq 1 ] && [ -d "${entries[0]}" ]; then
    src="${entries[0]}"
  fi

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "${src}/." "$dest/"
  echo "$VERSION" > "${dest}/.version"
  rm -rf "$tmp"
  trap - EXIT
  echo "LiveKit SDK ${VERSION} for ${platform} installed in ${dest}."
done
