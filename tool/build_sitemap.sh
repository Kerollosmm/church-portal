#!/usr/bin/env bash
# Replaces <out> (default build/web/sitemap.xml) with a sitemap generated from
# Firestore (ADR-038): tool/export_public_content.js reads the public content
# READ-ONLY with $GOOGLE_APPLICATION_CREDENTIALS, tool/gen_sitemap.dart applies
# the app's own indexing rules (lib/domain/sitemap.dart), and the result is
# checked before it replaces anything.
#
# Never fails the build: on any problem (no key, Firestore unreachable,
# generation or validation error) it prints a ::warning:: and leaves the
# static copy from web/sitemap.xml in place.
set -uo pipefail
OUT=${1:-build/web/sitemap.xml}
ORIGIN=https://maximos-domadios-church.web.app
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fallback() {
  echo "::warning::sitemap: $1 — keeping the static web/sitemap.xml"
  exit 0
}

[ -f "$OUT" ] || fallback "$OUT not found (build first)"
if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] || [ ! -s "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
  fallback "no service-account credentials"
fi
(cd tool && npm install --no-save --no-audit --no-fund --loglevel=error) >/dev/null 2>&1 || fallback "npm install failed"
# Ten sequential reads with a 30 s limit each (export_public_content.js): 300 s + margin.
timeout 330 node tool/export_public_content.js "$TMP/export.json" || fallback "Firestore read failed"
timeout 600 dart run tool/gen_sitemap.dart "$TMP/export.json" "$TMP/sitemap.xml" || fallback "generation failed"
python3 - "$TMP/sitemap.xml" "$ORIGIN" <<'PY' || fallback "validation failed"
import sys
import xml.etree.ElementTree as ET

path, origin = sys.argv[1], sys.argv[2]
ns = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
root = ET.parse(path).getroot()
assert root.tag == ns + "urlset", root.tag
locs = [u.findtext(ns + "loc") or "" for u in root.findall(ns + "url")]
assert origin + "/" in locs, "home page missing"
assert all(l.startswith(origin + "/") for l in locs), "foreign URL"
assert len(locs) == len(set(locs)), "duplicate URL"
assert len(locs) <= 50000, "too many URLs"
print(f"sitemap OK: {len(locs)} URLs")
PY
# Copy next to $OUT, then rename over it: a failed copy never leaves a
# truncated sitemap behind (the static copy stays in place).
cp "$TMP/sitemap.xml" "$OUT.tmp" || { rm -f "$OUT.tmp"; fallback "copy failed"; }
mv -f "$OUT.tmp" "$OUT" || { rm -f "$OUT.tmp"; fallback "replace failed"; }
echo "::notice::sitemap.xml generated from Firestore ($(grep -c '<url>' "$OUT") URLs)"
