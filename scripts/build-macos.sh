#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined tests/mt7902_codec_test.c \
    -framework CoreFoundation -framework IOKit -o build/mt7902_codec_test
build/mt7902_codec_test
xcodebuild -resolvePackageDependencies -project HeliPort.xcodeproj -scheme HeliPort \
    -derivedDataPath build -onlyUsePackageVersionsFromResolvedFile
xcodebuild -project HeliPort.xcodeproj -scheme HeliPort -configuration Release \
    -derivedDataPath build -disableAutomaticPackageResolution ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET=13.0 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
app=build/Build/Products/Release/HeliPort-MT7902.app
test -f "$app/Contents/MacOS/HeliPort-MT7902"
# No upstream update service is configured; sign this fork's local app and embedded helpers ad hoc.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/HeliPort-MT7902" -verify_arch x86_64
python3 scripts/package.py
