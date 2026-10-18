#!/bin/zsh
# Packs Plattenregal into a DMG whose window shows the app, an arrow and the
# Applications folder on a background in the colors of Klassisch with a
# record at the foot (dmg-background.swift). Writes
# dist/Plattenregal-<version>.dmg. The guides travel inside the app only
# (Hilfe › Handbuch); before the Release build make-guide.swift renews
# Plattenregal/Handbuch.pdf and Handbook.pdf if the brochure or the version
# changed.
#
#   Scripts/make-dmg.sh                       (builds Release first)
#   Scripts/make-dmg.sh <Plattenregal.app>    (e.g. exported from an archive)
#
# The Finder lays the window out, so the terminal needs the automation
# permission for the Finder once (macOS asks). The app is not notarized.
set -euo pipefail
cd "${0:A:h}/.."

NAME=Plattenregal
GUIDE=Handbuch.pdf
GUIDE_EN=Handbook.pdf
if [[ -n ${1:-} ]]; then
  APP=${1:A}
else
  SETTINGS=$(xcodebuild -scheme $NAME -configuration Release -showBuildSettings 2>/dev/null)
  MARKETING=$(awk '/ MARKETING_VERSION /{print $3; exit}' <<< $SETTINGS)
  swift Scripts/make-guide.swift "$NAME/$GUIDE" "$MARKETING" --if-changed
  swift Scripts/make-guide.swift "$NAME/$GUIDE_EN" "$MARKETING" --en --if-changed
  xcodebuild -scheme $NAME -configuration Release build | grep -E "error:|BUILD" || true
  APP="$(awk '/ BUILT_PRODUCTS_DIR /{print $3; exit}' <<< $SETTINGS)/$NAME.app"
fi
[[ -d $APP ]] || { echo "App nicht gefunden: $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT=dist/$NAME-$VERSION.dmg
for guide in $GUIDE $GUIDE_EN; do
  [[ -f $APP/Contents/Resources/$guide ]] || { echo "Kein $guide in der App: $APP" >&2; exit 1; }
done
MOUNT=/Volumes/$NAME
[[ -e $MOUNT ]] && { echo "$MOUNT ist schon eingehängt – bitte zuerst auswerfen." >&2; exit 1; }

WORK=$(mktemp -d)
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# Contents: the app, a link to /Applications, the
# hidden background (1x and 2x in one TIFF, so the Finder picks the sharp
# one on Retina).
mkdir -p "$WORK/src/.background"
ditto "$APP" "$WORK/src/$NAME.app"
ln -s /Applications "$WORK/src/Applications"
swift Scripts/dmg-background.swift "$WORK/bg.png" 1
swift Scripts/dmg-background.swift "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/src/.background/background.tiff" 2>/dev/null
ICNS="$APP/Contents/Resources/AppIcon.icns"
[[ -f $ICNS ]] && cp "$ICNS" "$WORK/src/.VolumeIcon.icns"

hdiutil create -quiet -srcfolder "$WORK/src" -volname $NAME -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"
[[ -f $MOUNT/.VolumeIcon.icns ]] && xcrun SetFile -a C "$MOUNT"

# Window 540 × 380 like the background (bounds include the 32 pt title bar);
# icon centers as in dmg-background.swift.
layout() {
  osascript <<EOF
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 740, 532}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 112
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set position of item "$NAME.app" of container window to {140, 178}
    set position of item "Applications" of container window to {400, 178}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF
}

# The Finder writes .DS_Store when it likes; now and then it kept the window
# bounds but not the background and icon size. Wait until both are stored,
# otherwise lay out again.
stored() {
  python3 -I - "$MOUNT/.DS_Store" <<'PY'
import plistlib, sys
try:
    data = open(sys.argv[1], 'rb').read()
    i = data.find(b'icvpblob')
    length = int.from_bytes(data[i + 8:i + 12], 'big')
    options = plistlib.loads(data[i + 12:i + 12 + length])
    sys.exit(0 if options.get('backgroundType') == 2 and options.get('iconSize') == 112 else 1)
except Exception:
    sys.exit(1)
PY
}
for attempt in 1 2 3; do
  layout
  for _ in {1..20}; do stored && break 2; sleep 0.5; done
  echo "Finder hat das Layout nicht gespeichert – neuer Versuch ($attempt)." >&2
done
stored || { echo "Layout ließ sich nicht speichern." >&2; exit 1; }

chmod -Rf go-w "$MOUNT"
sync
hdiutil detach -quiet "$MOUNT"
mkdir -p dist
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT"
echo "$OUT"
