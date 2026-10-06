#!/bin/zsh
# Takes the pictures of the tour (see TourView.swift) from the demo and puts
# them into Assets.xcassets/Tour: every picture in German and English, light
# and dark. Run again after the pages changed:
#
#   Scripts/tour-screenshots.sh
#   Scripts/tour-screenshots.sh --raw <folder>   (only the window shots, German and light, to measure crops)
#
# Builds the Debug app first. Needs the screen recording permission for the
# terminal (screencapture). The demo never touches the own collection.
set -euo pipefail
cd "${0:A:h}/.."

RAW_ONLY=""
[[ ${1:-} == "--raw" ]] && RAW_ONLY=${2:?Ordner fehlt}

xcodebuild -scheme Plattenregal -configuration Debug build | grep -E "error:|BUILD" || true
APP="$(xcodebuild -scheme Plattenregal -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/Plattenregal.app"
ASSETS=Plattenregal/Assets.xcassets/Tour
WORK=$(mktemp -d)
mkdir "$WORK/shots"
trap 'rm -rf "$WORK"' EXIT

# Window shots: name | launch arguments
SHOTS=(
  "collection|--preview-page=Collection"
  "wantlist|--preview-page=Wantlist"
  "shelf|--preview-page=Regal"
  "place|--preview-page=Regal --preview-place=Bonobo"
  "add|--preview-page=Regal --preview-add"
  "statistics|--preview-page=Statistik"
  "discogs|--settings-tab=Discogs"
  "export|--settings-tab=Export"
  "backup|--settings-tab=Sicherung"
)

# Pictures of the tour: name | window shot | crop "height width y x" in pixels
# of the window shot (Retina, window 1223 × 793 pt). Two per page, fanned out.
PICTURES=(
  "collection|collection|1000 1650 155 45"
  "wantlist|wantlist|830 1650 155 45"
  "account|discogs|372 1455 370 497"
  "sync|discogs|310 1455 752 497"
  "rack|shelf|450 1200 145 45"
  "table|shelf|560 1300 640 45"
  "add|add|950 1676 151 384"
  "place|place|640 1250 230 45"
  "value|statistics|570 1500 145 72"
  "facts|statistics|360 1500 745 72"
  "export|export|465 1455 367 497"
  "backup|backup|820 1455 367 497"
)

# The app's process, for this demo instance only (an installed Plattenregal keeps running).
quit_demo() {
  local pid
  for pid in $(pgrep -x Plattenregal || true); do
    [[ $(ps -o command= -p $pid) == "$APP"* ]] && kill $pid
  done
  sleep 2
}

capture() {  # language appearance
  local shot name arguments
  for shot in $SHOTS; do
    name=${shot%%|*}; arguments=${shot#*|}
    open -n "$APP" --args --demo --screenshots ${=arguments} -appearanceMode $2 -AppleLanguages "($1)"
    sleep 6
    screencapture -o -l"$(swift Scripts/winid.swift)" "$WORK/shots/$name-$1-$2.png"
    quit_demo
    echo "$name $1 $2"
  done
}

if [[ -n $RAW_ONLY ]]; then
  capture de light
  mkdir -p "$RAW_ONLY"
  for shot in $SHOTS; do cp "$WORK/shots/${shot%%|*}-de-light.png" "$RAW_ONLY/${shot%%|*}.png"; done
  exit 0
fi

for language in de en; do
  for appearance in light dark; do
    capture $language $appearance
    for picture in $PICTURES; do
      name=${picture%%|*}; rest=${picture#*|}; shot=${rest%%|*}; crop=(${=rest#*|})
      out="$WORK/$name-$language-$appearance"
      cp "$WORK/shots/$shot-$language-$appearance.png" "$out.png"
      sips -c $crop[1] $crop[2] --cropOffset $crop[3] $crop[4] "$out.png" >/dev/null
      sips -Z 1200 -s format jpeg -s formatOptions 82 "$out.png" --out "$out.jpg" >/dev/null
    done
  done
done

# One image set per picture and language, with a dark variant.
rm -rf "$ASSETS"
mkdir -p "$ASSETS"
print '{\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "provides-namespace" : true }\n}' > "$ASSETS/Contents.json"
for picture in $PICTURES; do
  name=${picture%%|*}
  for language in de en; do
    set_dir="$ASSETS/$name-$language.imageset"
    mkdir -p "$set_dir"
    cp "$WORK/$name-$language-light.jpg" "$set_dir/$name-$language.jpg"
    cp "$WORK/$name-$language-dark.jpg" "$set_dir/$name-$language-dark.jpg"
    cat > "$set_dir/Contents.json" <<EOF
{
  "images" : [
    { "filename" : "$name-$language.jpg", "idiom" : "universal", "scale" : "2x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "$name-$language-dark.jpg", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
  done
done
echo "Fertig: $ASSETS"
