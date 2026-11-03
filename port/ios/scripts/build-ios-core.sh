#!/usr/bin/env bash
#
# Builds the iOS arm64 core archive (build/ios-core/libre4.a).
#
#   bash port/ios/scripts/build-ios-core.sh
#
# Requirements: macOS with Xcode and CMake 3.22+. This is the phase-1 gate: the
# scheduler, its Mach-O fcontext backend and the ported core have to compile
# against the iPhoneOS device SDK. The archive is not linked into the app yet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD_DIR="${RE4_IOS_CORE_BUILD_DIR:-${ROOT}/build/ios-core}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-Debug}"
JOBS="${RE4_JOBS:-3}"

echo "Xcode:"
xcodebuild -version
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
echo "Build dir: ${BUILD_DIR}"

cmake -S "${ROOT}/port" -B "${BUILD_DIR}" \
    -DCMAKE_TOOLCHAIN_FILE="${ROOT}/port/ios/cmake/ios.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DRE4_BUILD_TESTS=OFF

cmake --build "${BUILD_DIR}" --target re4_ios_core --parallel "${JOBS}"

ARCHIVE="${BUILD_DIR}/libre4.a"
if [ ! -f "${ARCHIVE}" ]; then
    echo "error: ${ARCHIVE} nao foi gerado." >&2
    exit 1
fi

echo "Archive: ${ARCHIVE}"
echo "Architectures: $(lipo -archs "${ARCHIVE}")"
# Capture the symbol table first: `nm | grep -q` would let grep exit early,
# SIGPIPE nm and fail this script under `set -o pipefail` even on a match.
NM_OUT="${BUILD_DIR}/libre4.nm.txt"
nm -g "${ARCHIVE}" > "${NM_OUT}" 2>/dev/null
if ! grep -q '_make_fcontext$' "${NM_OUT}"; then
    echo "error: libfcontext (make_fcontext) nao esta no archive." >&2
    exit 1
fi
if ! grep -q '_jump_fcontext$' "${NM_OUT}"; then
    echo "error: libfcontext (jump_fcontext) nao esta no archive." >&2
    exit 1
fi
echo "fcontext: make/jump presentes"
