#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
echo "Host architecture: $(uname -m)"
xcodebuild -version
plutil -lint HeliPort.xcodeproj/project.pbxproj
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
echo "macOS SDK: $sdk_version"
if [[ "${sdk_version%%.*}" -lt 26 ]]; then
    echo "Xcode with the macOS 26 SDK or newer is required for the Tahoe appearance." >&2
    exit 1
fi
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined tests/mt7902_codec_test.c \
    -framework CoreFoundation -framework IOKit -o build/mt7902_codec_test
build/mt7902_codec_test
xcrun swiftc -swift-version 5 -parse-as-library -sanitize=address -g \
    'HeliPort/Supporting files/ConnectionAnimation.swift' \
    'HeliPort/Supporting files/MenuAppearance.swift' \
    'HeliPort/Supporting files/InterfaceDetails.swift' tests/app_lifecycle_test.swift \
    -o build/app_lifecycle_test
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 build/app_lifecycle_test
xcodebuild -resolvePackageDependencies -project HeliPort.xcodeproj -scheme HeliPort \
    -derivedDataPath build -onlyUsePackageVersionsFromResolvedFile
xcodebuild -list -project HeliPort.xcodeproj -derivedDataPath build -scheme HeliPort \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
xcodebuild -project HeliPort.xcodeproj -scheme HeliPort -configuration Release \
    -sdk macosx -destination 'generic/platform=macOS' \
    -derivedDataPath build -disableAutomaticPackageResolution ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET=13.0 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
app=build/Build/Products/Release/HeliPort-MT7902.app
test -f "$app/Contents/MacOS/HeliPort-MT7902"
# No upstream update service is configured; sign this fork's local app and embedded helpers ad hoc.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/HeliPort-MT7902" -verify_arch x86_64
lipo "$app/Contents/Library/LoginItems/HeliPort Launcher.app/Contents/MacOS/HeliPort Launcher" -verify_arch x86_64
python3 scripts/package.py
