#!/usr/bin/env bash
# Build Cyanide for iphoneos and package the resulting .app into a versioned IPA
# under build/, e.g. build/Cyanide-1.0.14.ipa, with a build/Cyanide.ipa
# symlink pointing at the latest build.
#
# Run as: ./scripts/build.sh
# Override defaults with env vars:
#   SCHEME, CONFIG (Debug|Release), SDK (iphoneos|iphonesimulator),
#   XCODEBUILD_DESTINATION (defaults to generic/platform=iOS for iphoneos)
#
# The version comes from CFBundleShortVersionString in the built Info.plist
# (= the MARKETING_VERSION build setting in the xcodeproj). Bump
# MARKETING_VERSION to ship a new version.
#
# Code signing is disabled — the IPA ships unsigned for sideload via
# AltStore / TrollStore / Sideloadly, which do their own signing.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${SCHEME:-Cyanide}"
CONFIG="${CONFIG:-Debug}"
SDK="${SDK:-iphoneos}"
XCODEBUILD_DESTINATION="${XCODEBUILD_DESTINATION:-}"
PROJECT="Cyanide.xcodeproj"
DERIVED="$PWD/build/DerivedData"
PRODUCT_DIR="$DERIVED/Build/Products/${CONFIG}-${SDK}"
APP_NAME="Cyanide.app"
IPA_LATEST="$PWD/build/Cyanide.ipa"

mkdir -p build

XCODEBUILD_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -sdk "$SDK"
    -configuration "$CONFIG"
    -derivedDataPath "$DERIVED"
)

if [ -z "$XCODEBUILD_DESTINATION" ] && [[ "$SDK" == iphoneos* ]]; then
    XCODEBUILD_DESTINATION="generic/platform=iOS"
fi

if [ -n "$XCODEBUILD_DESTINATION" ]; then
    XCODEBUILD_ARGS+=( -destination "$XCODEBUILD_DESTINATION" )
fi

echo "==> xcodebuild ($SCHEME / $CONFIG / $SDK)"
xcodebuild "${XCODEBUILD_ARGS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    build \
    | xcbeautify --quiet 2>/dev/null \
    || xcodebuild "${XCODEBUILD_ARGS[@]}" \
         CODE_SIGNING_ALLOWED=NO \
         build

APP_PATH="$PRODUCT_DIR/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "error: $APP_PATH not found after build" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Info.plist" 2>/dev/null || true)
if [ -z "$VERSION" ]; then
    echo "error: could not read CFBundleShortVersionString from $APP_PATH/Info.plist" >&2
    exit 1
fi

IPA_OUT="$PWD/build/Cyanide-${VERSION}.ipa"
IPA_BASENAME="$(basename "$IPA_OUT")"
LATEST_BASENAME="$(basename "$IPA_LATEST")"

echo "==> packaging $IPA_OUT (version $VERSION)"
STAGE="$(mktemp -d -t cyanide-ipa)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/"
rm -f "$IPA_OUT"
( cd "$STAGE" && zip -qry "$IPA_OUT" Payload )

# Keep an unversioned symlink so tooling / README references that expect the
# legacy path still resolve to the latest build.
rm -f "$IPA_LATEST"
( cd "$PWD/build" && ln -s "$IPA_BASENAME" "$LATEST_BASENAME" )

SIZE=$(du -h "$IPA_OUT" | cut -f1)
echo "==> wrote $IPA_OUT ($SIZE)"
echo "==> symlink $IPA_LATEST -> $IPA_BASENAME"
