#!/usr/bin/env bash
# Regenerates every logo/icon from the official parish seal (ImageMagick 7).
# Usage: tool/gen_branding.sh [path/to/seal-1024.(webp|png)]
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-assets/branding/seal_source.webp}"
BG="#470812"   # maroon sampled from the seal's background
B=assets/branding; W=web; R=android/app/src/main/res
mkdir -p "$B" "$W/icons"
[ "$SRC" = "$B/seal_source.webp" ] || cp "$SRC" "$B/seal_source.webp"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
magick "$B/seal_source.webp" -strip "$T/sq.png"                       # full-bleed square
# Round seal on transparency (outer gold ring ends ~r=497 of 1024).
magick "$T/sq.png" \( -size 1024x1024 xc:black -fill white -draw "circle 512,512 512,10" \) \
  -alpha off -compose CopyOpacity -composite "$T/round.png"
magick "$T/round.png" -filter Lanczos -resize 256x256 -strip "$B/seal.png"   # in-app logo
# Web
magick "$T/sq.png" -filter Lanczos -resize 192x192 -strip "$W/icons/Icon-192.png"
magick "$T/sq.png" -filter Lanczos -resize 512x512 -strip "$W/icons/Icon-512.png"
magick "$T/sq.png" -filter Lanczos -resize 180x180 -strip "$W/icons/apple-touch-icon.png"
for s in 192 512; do  # maskable: seal within the 80% safe circle
  inner=$(( s * 78 / 100 ))
  magick -size ${s}x${s} xc:"$BG" \( "$T/round.png" -filter Lanczos -resize ${inner}x${inner} \) \
    -gravity center -composite -strip "$W/icons/Icon-maskable-$s.png"
done
magick "$T/round.png" -filter Lanczos -resize 32x32 -strip "$W/favicon.png"
magick "$T/round.png" -filter Lanczos -resize 16x16 -strip "$W/favicon-16.png"
magick "$T/round.png" -define icon:auto-resize=48,32,16 "$W/favicon.ico"
magick -size 1200x630 xc:"$BG" \( "$T/round.png" -filter Lanczos -resize 540x540 \) \
  -gravity center -composite -strip -quality 85 "$W/og-image.jpg"
# Android legacy launcher icons + adaptive foreground (108dp, seal inside the 66dp safe zone)
for d in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  IFS=: read -r n s f <<<"$d"
  magick "$T/sq.png" -filter Lanczos -resize ${s}x${s} -strip "$R/mipmap-$n/ic_launcher.png"
  inner=$(( f * 64 / 108 ))
  magick -size ${f}x${f} xc:none \( "$T/round.png" -filter Lanczos -resize ${inner}x${inner} \) \
    -gravity center -composite -strip "$R/mipmap-$n/ic_launcher_foreground.png"
done
echo "branding regenerated"
