#!/bin/zsh
# Nimmt die Fenster für die Produktbilder (Marketing/) aus der ECHTEN Sammlung
# auf – nicht aus der Demo. Baut Debug, startet die App je Bild einmal mit
# den Debug-Schaltern (--preview-page …), holt sie nach vorn und fotografiert
# das Fenster mit screencapture (ohne Systemschatten, den setzt die Vorlage).
# Dazu kommen 72 Cover aus dem Cover-Cache für die Cover-Wand.
#
#   zsh Scripts/marketing-shots.sh
#
# Braucht die Freigabe „Bildschirmaufnahme“ fürs Terminal und einen
# entsperrten Bildschirm; Plattenregal darf nicht laufen. Das Fenster liegt
# links auf dem Bildschirm, der Mauszeiger sollte rechts daneben ruhen
# (sonst erscheinen Cover unter ihm hervorgehoben). Die Collection ist
# zufällig gemischt, jede Aufnahme zeigt also andere Platten.
# Ergebnis: Marketing/Aufnahmen/*.png und Marketing/Aufnahmen/Cover/*.jpg
# (nicht im Repository, jederzeit neu erzeugbar).
set -e
ROOT=${0:A:h:h}
OUT=$ROOT/Marketing/Aufnahmen
CONTAINER=~/Library/Containers/de.private.Plattenregal/Data
PREF=$CONTAINER/Library/Preferences/de.private.Plattenregal
COVERS="$CONTAINER/Library/Application Support/Plattenregal/Covers"
KEY="NSWindow Frame main"
W=1280; H=800

if pgrep -xq Plattenregal; then echo "Plattenregal läuft – bitte zuerst beenden." >&2; exit 1; fi
mkdir -p $OUT/Cover

echo "Debug-Build …"
xcodebuild -project $ROOT/Plattenregal.xcodeproj -scheme Plattenregal -configuration Debug build -quiet
PRODUCTS=$(xcodebuild -project $ROOT/Plattenregal.xcodeproj -scheme Plattenregal -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2}')
APP=$PRODUCTS/Plattenregal.app

# Fenster-ID des größten Plattenregal-Fensters.
WINID=$(mktemp -d)/winid
cat > $WINID.swift <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Plattenregal" && ($0[kCGWindowLayer as String] as? Int) == 0 }
let area = { (w: [String: Any]) -> Double in let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]; return (b["Width"] ?? 0) * (b["Height"] ?? 0) }
print(windows.max { area($0) < area($1) }?[kCGWindowNumber as String] as? Int ?? 0)
EOF
swiftc -O $WINID.swift -o $WINID

# Fenstergröße für die Aufnahmen, danach wieder die eigene.
PREVIOUS=$(defaults read $PREF $KEY 2>/dev/null || true)
restore() { if [[ -n $PREVIOUS ]]; then defaults write $PREF $KEY "$PREVIOUS"; else defaults delete $PREF $KEY 2>/dev/null || true; fi }
# Auch bei Abbruch oder Fehler zurücksetzen (zsh: TRAPEXIT).
TRAPEXIT() { restore }

# shot <Name> <Design: atelier|none> <light|dark> <Wartezeit> [Schalter …]
shot() {
  local name=$1 design=$2 mode=$3 wait=$4; shift 4
  # Links, senkrecht mittig im sichtbaren Bereich (Menüleiste und Dock).
  local visible=(${(s: :)$(osascript -l JavaScript -e 'ObjC.import("AppKit"); const f=$.NSScreen.mainScreen.visibleFrame; const s=$.NSScreen.mainScreen.frame; [f.origin.y, f.size.height, s.size.width, s.size.height].join(" ")')})
  local y=$(( ${visible[1]%.*} + (${visible[2]%.*} - H) / 2 ))
  defaults write $PREF $KEY "8 $y $W $H 0 0 ${visible[3]%.*} $(( ${visible[1]%.*} + ${visible[2]%.*} ))"
  # Erst die Paare, dann die Schalter (siehe README, Startargumente).
  open -n -a $APP --args -signatureDesign $design -appearanceMode $mode -atelierCoverFrame sleeve -tourSeen YES "$@"
  sleep $wait
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $(pgrep -n -x Plattenregal)) to true" >/dev/null
  sleep 1.5
  screencapture -x -o -l $($WINID) $OUT/$name.png
  pkill -x Plattenregal; sleep 2
  echo "$name.png"
}

shot collection        atelier light 9  --preview-page=Collection
shot collection-dark   atelier dark  9  --preview-page=Collection
shot modern            none    light 9  --preview-page=Collection
shot wantlist          atelier light 9  --preview-page=Wantlist
shot shelf             atelier light 9  --preview-page=Regal
shot shelf-dark        atelier dark  9  --preview-page=Regal
shot sortcheck         atelier light 9  --preview-page=Regal --preview-sortcheck --preview-sortcheck-done=1
shot stats             atelier light 11 --preview-page=Statistik
shot detail            atelier light 11 --preview-page=Statistik --preview-detail=Moonbeam

# Cover für die Wand: zufällig, quadratisch beschnitten, 400 px.
rm -rf $OUT/Cover; mkdir -p $OUT/Cover
i=0
for f in ${(f)"$(ls $COVERS | sort -R)"}; do
  w=$(sips -g pixelWidth "$COVERS/$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$COVERS/$f" 2>/dev/null | awk '/pixelHeight/{print $2}')
  [[ -z $w || $w -lt 400 ]] && continue
  # Nur annähernd quadratische Cover (Plattenhüllen), keine Fotos.
  (( w * 100 / h < 95 || w * 100 / h > 105 )) && continue
  i=$((i + 1)); n=$(printf %02d $i)
  m=$(( w < h ? w : h ))
  sips -s format jpeg -s formatOptions 88 -c $m $m -Z 400 "$COVERS/$f" --out $OUT/Cover/$n.jpg >/dev/null
  (( i == 72 )) && break
done
echo "$i Cover"
