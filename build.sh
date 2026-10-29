#!/bin/zsh
# Builds "Dock Minimize.app" into build/.
#   ./build.sh            build for this Mac, signed for local use
#   ./build.sh install    same, then copy it to /Applications and launch it
#   ./build.sh release    universal build, signed with Developer ID, notarized and zipped for sharing
set -euo pipefail
cd "${0:A:h}"

MODE="${1:-}"
APP="build/Dock Minimize.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"

if [[ "$MODE" == "release" ]]; then
    ARCHS=(--arch arm64 --arch x86_64)
    CERT="Developer ID Application"
else
    ARCHS=()
    CERT="Apple Development"
fi

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/DockMinimize"

mkdir -p build
if [[ ! -f build/AppIcon.icns ]]; then
    mkdir -p build/AppIcon.iconset
    swift Scripts/make-icon.swift build/icon-1024.png
    for px in 16 32 128 256 512; do
        sips -z $px $px build/icon-1024.png --out "build/AppIcon.iconset/icon_${px}x${px}.png" >/dev/null
        sips -z $((px * 2)) $((px * 2)) build/icon-1024.png --out "build/AppIcon.iconset/icon_${px}x${px}@2x.png" >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DockMinimize"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A real certificate keeps the Accessibility permission across rebuilds; an ad hoc signature loses it every time.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' -v cert="$CERT" 'index($2, cert) == 1 { print $2; exit }')}"

if [[ "$MODE" != "release" ]]; then
    codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
    echo "Built $APP (signed with ${IDENTITY:-ad hoc signature})"
    if [[ "$MODE" == "install" ]]; then
        pkill -x DockMinimize 2>/dev/null || true
        rm -rf "/Applications/Dock Minimize.app"
        cp -R "$APP" /Applications/
        open "/Applications/Dock Minimize.app"
        echo "Installed to /Applications and launched"
    fi
    exit 0
fi

if [[ -z "$IDENTITY" ]]; then
    echo "No \"Developer ID Application\" certificate found. Set SIGN_IDENTITY to use another one." >&2
    exit 1
fi
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

# Notarization needs stored credentials once: xcrun notarytool store-credentials DockMinimize --apple-id ... --team-id ...
ZIP="build/DockMinimize-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-DockMinimize}" --wait
xcrun stapler staple "$APP"

# Zip again so the download carries the stapled ticket and opens without a network check.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Release ready: $ZIP"
