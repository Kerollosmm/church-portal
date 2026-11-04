#!/usr/bin/env bash
# Regenerates every logo/icon from the parish seal (ImageMagick 7).
#
# The master is the round seal (white disc, gold double ring) on a TRANSPARENT
# background, square, >= 1024 px (assets/branding/seal_source.webp, lossless).
# To replace the logo: crop the new artwork to its circle with transparency
# outside the ring, then run:   tool/gen_branding.sh [path/to/round-seal.(webp|png)]
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-assets/branding/seal_source.webp}"
BG="#470812"     # maroon (the seal tab / theme primary dark): maskable + adaptive backgrounds, OG card
B=assets/branding; W=web; R=android/app/src/main/res
mkdir -p "$B" "$W/icons"
if ! { [ -e "$B/seal_source.webp" ] && [ "$SRC" -ef "$B/seal_source.webp" ]; }; then
  magick "$SRC" -strip -define webp:lossless=true "$B/seal_source.webp"
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
magick "$B/seal_source.webp" -strip -alpha on "$T/round.png"

# Downscale with Lanczos; small sizes get a light unsharp so the ring and the
# church stay crisp (the seal's small lettering cannot be legible at 16-48 px).
shrink() { # src size out [extra...]
  local src=$1 s=$2 out=$3; shift 3
  local sharp=()
  [ "$s" -le 64 ] && sharp=(-unsharp 0x0.6+0.8+0.02)
  [ "$s" -gt 64 ] && [ "$s" -le 200 ] && sharp=(-unsharp 0x0.5+0.4+0.02)
  magick "$src" -filter Lanczos -resize "${s}x${s}" "${sharp[@]}" "$@" -strip "$out"
}
# Seal centred at PCT % of an SxS canvas filled with COLOUR (none = transparent).
onbg() { # size pct colour out
  local s=$1 inner=$(( $1 * $2 / 100 )) c=$3 out=$4
  shrink "$T/round.png" "$inner" "$T/inner_${s}_${2}.png"
  magick -size "${s}x${s}" xc:"$c" "$T/inner_${s}_${2}.png" -gravity center -composite -strip "$out"
}

# In-app logo (header tab, drawer, footer, admin) and the web splash: 384 px
# (sharp at 120 css px on 3x screens; quantized to < 35 KB).
shrink "$T/round.png" 384 "$B/seal.png"
if python3 -c "import PIL" >/dev/null 2>&1; then
  python3 -c "from PIL import Image; im = Image.open('$B/seal.png'); im.quantize(colors=256, method=Image.Quantize.FASTOCTREE).save('$B/seal.png', format='PNG', optimize=True)"
elif command -v pngquant >/dev/null 2>&1; then
  pngquant --force --quality=80-95 --output "$B/seal.png" "$B/seal.png"
fi
# Web: favicons, PWA "any" icons (round on transparency), Apple touch icon
# (opaque: iOS ignores transparency), maskable (seal inside the 80 % safe circle).
shrink "$T/round.png" 32 "$W/favicon.png"
shrink "$T/round.png" 16 "$W/favicon-16.png"
for s in 16 32 48; do shrink "$T/round.png" "$s" "$T/fav$s.png"; done
magick "$T/fav16.png" "$T/fav32.png" "$T/fav48.png" "$W/favicon.ico"
shrink "$T/round.png" 192 "$W/icons/Icon-192.png"
shrink "$T/round.png" 512 "$W/icons/Icon-512.png"
onbg 180 94 white "$W/icons/apple-touch-icon.png"
for s in 192 512; do onbg "$s" 78 "$BG" "$W/icons/Icon-maskable-$s.png"; done
shrink "$T/round.png" 540 "$T/og_seal.png"
magick -size 1200x630 xc:"$BG" "$T/og_seal.png" -gravity center -composite -strip -quality 88 "$W/og-image.jpg"

# Android: legacy launcher (round seal, transparent corners), adaptive
# foreground (108 dp canvas, seal inside the 66 dp safe zone; background is
# @color/ic_launcher_background = $BG) and the launch-screen seal (128 dp).
for d in mdpi:48:108:128 hdpi:72:162:192 xhdpi:96:216:256 xxhdpi:144:324:384 xxxhdpi:192:432:512; do
  IFS=: read -r n s f l <<<"$d"
  shrink "$T/round.png" "$s" "$R/mipmap-$n/ic_launcher.png"
  onbg "$f" 59 none "$R/mipmap-$n/ic_launcher_foreground.png"
  shrink "$T/round.png" "$l" "$R/mipmap-$n/launch_image.png"
done
echo "branding regenerated"
