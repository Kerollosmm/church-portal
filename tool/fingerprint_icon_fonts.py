#!/usr/bin/env python3
"""Gives the tree-shaken icon fonts of a Flutter web build a content-hashed
file name (PR #23).

`flutter build web` subsets MaterialIcons-Regular.otf / CupertinoIcons.ttf to
the icons the code uses and writes them under the SAME file name every build.
Hosting serves fonts with a 7-day cache (firebase.json), so a browser that
cached an older subset kept it after a deploy that started using new icons:
those icons drew as blank space (the admin menu entries added in PR #18).

This script renames each icon font to `<name>.<sha256[:12]>.<ext>` and points
assets/FontManifest.json (served no-cache) at the new name, so a deploy that
changes the subset changes the URL. Run it after `flutter build web`:

    python3 tool/fingerprint_icon_fonts.py [build/web]

Idempotent: an already fingerprinted entry is left alone. Exits non-zero when
the manifest names a font file that does not exist.
"""

import hashlib
import json
import os
import re
import sys

ICON_FONTS = ('fonts/MaterialIcons-Regular.otf', 'packages/cupertino_icons/assets/CupertinoIcons.ttf')
_HASHED = re.compile(r'\.[0-9a-f]{12}\.(otf|ttf)$')


def fingerprint(web_dir: str) -> list[tuple[str, str]]:
    assets = os.path.join(web_dir, 'assets')
    manifest_path = os.path.join(assets, 'FontManifest.json')
    with open(manifest_path, encoding='utf-8') as f:
        manifest = json.load(f)
    renamed = []
    for family in manifest:
        for font in family.get('fonts', []):
            asset = font.get('asset', '')
            path = os.path.join(assets, asset)
            if asset in ICON_FONTS and not _HASHED.search(asset):
                with open(path, 'rb') as fh:
                    digest = hashlib.sha256(fh.read()).hexdigest()[:12]
                stem, ext = os.path.splitext(asset)
                new_asset = f'{stem}.{digest}{ext}'
                os.replace(path, os.path.join(assets, new_asset))
                font['asset'] = new_asset
                renamed.append((asset, new_asset))
                path = os.path.join(assets, new_asset)
            if not os.path.isfile(path):
                sys.exit(f'FontManifest names a missing font: {asset}')
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, separators=(',', ':'))
    return renamed


if __name__ == '__main__':
    out = fingerprint(sys.argv[1] if len(sys.argv) > 1 else 'build/web')
    for old, new in out:
        print(f'{old} -> {new}')
    if not out:
        print('icon fonts already fingerprinted (or none in the build)')
