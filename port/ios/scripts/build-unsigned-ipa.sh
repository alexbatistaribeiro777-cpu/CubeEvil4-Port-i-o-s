#!/usr/bin/env bash
#
# Builds port/ios and packages an *unsigned* .ipa.
#
#   bash port/ios/scripts/build-unsigned-ipa.sh
#
# Requirements: macOS with Xcode command line tools, xcodegen (brew install xcodegen).
# The unsigned IPA can be signed for a device with Sideloadly/AltStore and a free Apple ID.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${IOS_DIR}"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen nao encontrado. Instale com 'brew install xcodegen'." >&2
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild nao encontrado. Instale o Xcode." >&2
    exit 1
fi

echo "Xcode:"
xcodebuild -version
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"

xcodegen generate --spec project.yml

rm -rf build
mkdir -p build

set -o pipefail
xcodebuild \
    -project CubeEvil4.xcodeproj \
    -scheme CubeEvil4 \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    build 2>&1 | tee build/xcodebuild.log

APP="build/DerivedData/Build/Products/Release-iphoneos/CubeEvil4.app"
if [ ! -d "${APP}" ]; then
    echo "error: ${APP} nao foi gerado." >&2
    exit 1
fi

IPA_DIR="build/ipa"
rm -rf "${IPA_DIR}"
mkdir -p "${IPA_DIR}/Payload"
cp -R "${APP}" "${IPA_DIR}/Payload/"

(
    cd "${IPA_DIR}"
    zip -qry CubeEvil4-unsigned.ipa Payload
)

IPA="${IPA_DIR}/CubeEvil4-unsigned.ipa"
echo "IPA: ${IPA}"
echo "Tamanho: $(du -h "${IPA}" | cut -f1)"
echo "Assinatura: nenhuma (CODE_SIGNING_ALLOWED=NO). Assine com Sideloadly/AltStore."
