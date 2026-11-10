#!/bin/bash
# Builds the website as a plain folder for a web host (Cloudflare Pages):
# dist/Webseite/ with index.html as a full document and real copies of the
# images. The photos with real covers come from Marketing/Webseite/ (local
# only, not in the repository; Scripts/web-images.swift) and only end up in
# dist/, which is not versioned either.
#
#   Scripts/make-website.sh           (build the folder)
#   Scripts/make-website.sh deploy    (build and upload with Wrangler)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=Webseite
OUT=dist/Webseite
PHOTOS=Marketing/Webseite
GUIDE_IMAGES=Handbuch/Bilder
PROJECT=plattenregal

if [[ ! -d $PHOTOS/de || ! -d $PHOTOS/en || ! -d $PHOTOS/Cover ]]; then
  echo "Fehlt: $PHOTOS/de, en und Cover (swift Scripts/web-images.swift)" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/Bilder/de" "$OUT/Bilder/en" "$OUT/Fotos/de" "$OUT/Fotos/en" "$OUT/Fotos/Cover"

# Only what the page loads: the icon, the Discogs settings picture, the photos
# of both languages and the covers of the wall.
cp "$GUIDE_IMAGES/icon.png" "$OUT/Bilder/"
for lang in de en; do
  cp "$GUIDE_IMAGES/$lang/settings-discogs.jpg" "$OUT/Bilder/$lang/"
  cp "$PHOTOS/$lang"/*.jpg "$PHOTOS/$lang"/*.png "$OUT/Fotos/$lang/"
done
cp "$PHOTOS/Cover"/*.jpg "$OUT/Fotos/Cover/"

covers=$(ls "$OUT/Fotos/Cover" | wc -l | tr -d ' ')
if [[ $covers -lt 48 ]]; then
  echo "Nur $covers Cover in $PHOTOS/Cover, die Wand braucht 48." >&2
  exit 1
fi

# The artifact service wraps the page in a document of its own; a web host
# serves it as it is, so it gets doctype, language, viewport, description and
# icon here. The Claude-only meta line is dropped.
{
  cat <<'HEAD'
<!doctype html>
<html lang="de">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="Plattenregal holt deine Sammlung aus Discogs und merkt sich, in welchem Regal, in welchem Fach und an welcher Stelle jede Platte steht. Kostenlos für den Mac.">
<meta property="og:title" content="Plattenregal">
<meta property="og:description" content="Deine Platten. Und wo jede steht. Kostenlos für den Mac.">
<link rel="icon" type="image/png" href="Bilder/icon.png">
<link rel="apple-touch-icon" href="Bilder/icon.png">
HEAD
  grep -v -e '^<meta charset="utf-8">$' -e 'name="claude:' "$SRC/index.html"
} > "$OUT/index.html"

size=$(du -sh "$OUT" | cut -f1)
echo "Fertig: $OUT ($size, $covers Cover)"

if [[ ${1:-} == deploy ]]; then
  npx --yes wrangler pages deploy "$OUT" --project-name "$PROJECT"
else
  echo "Hochladen: Scripts/make-website.sh deploy"
  echo "       oder den Ordner im Cloudflare-Dashboard unter Workers & Pages → Pages → Upload assets hineinziehen."
fi
