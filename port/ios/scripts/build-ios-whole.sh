#!/usr/bin/env bash
#
# Builds the whole-program port (main.dol units + the 114 REL modules) for iOS
# as one static archive: build/ios-whole/libre4_whole.a.
#
#   bash port/ios/scripts/build-ios-whole.sh
#
# This is the phase-2 loop. `port/whole/CMakeLists.txt` switches to
# RE4_WHOLE_LINK=OFF on iOS: no ELF link plan, no shared libraries and no
# trampolines; every unit is compiled for arm64 against the iPhoneOS device SDK.
# The archive is not linked into the app yet; this script exists so the real
# compiler errors of the game code on Darwin/arm64 are visible in CI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD_DIR="${RE4_IOS_WHOLE_BUILD_DIR:-${ROOT}/build/ios-whole}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-Debug}"
JOBS="${RE4_JOBS:-3}"

echo "Xcode:"
xcodebuild -version
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
echo "Build dir: ${BUILD_DIR}"

cmake -S "${ROOT}/port/whole" -B "${BUILD_DIR}" \
    -DCMAKE_TOOLCHAIN_FILE="${ROOT}/port/ios/cmake/ios.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DRE4_WHOLE_LINK=OFF

cmake --build "${BUILD_DIR}" --target re4_whole --parallel "${JOBS}"

ARCHIVE="${BUILD_DIR}/libre4_whole.a"
if [ ! -f "${ARCHIVE}" ]; then
    echo "error: ${ARCHIVE} nao foi gerado." >&2
    exit 1
fi

echo "Archive: ${ARCHIVE}"
echo "Architectures: $(lipo -archs "${ARCHIVE}")"
