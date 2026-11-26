#!/usr/bin/env python3
"""Gives main.dart.js (and its sourcemap) a content-hashed filename (PR 6G).

`flutter build web --release` writes main.dart.js under the same name every build.
To allow Firebase Hosting to serve /main.<hash>.dart.js with long-lived immutable
caching (`max-age=31536000, immutable`) without stalling return visitors on stale
code, this script renames ONLY `main.dart.js` -> `main.<sha256[:12]>.dart.js`
and `main.dart.js.map` -> `main.<sha256[:12]>.dart.js.map`, updates the trailing
`//# sourceMappingURL=` comment, and updates `mainJsPath` in `flutter_bootstrap.js`.

Deferred `main.dart.js_<N>.part.js` chunks are intentionally NOT renamed because
dart2js compiles their exact filenames into `main.dart.js`.

Usage:
    python3 tool/fingerprint_web_bundle.py [build/web]

Idempotent: if `main.dart.js` was already fingerprinted and `flutter_bootstrap.js`
references the hashed file, re-running is a no-op.
"""

import hashlib
import os
import re
import sys

_HASHED_MAIN = re.compile(r'^main\.[0-9a-f]{12}\.dart\.js$')
_HASHED_MAIN_OR_MAP = re.compile(r'^main\.[0-9a-f]{12}\.dart\.js(?:\.map)?$')
_SOURCE_MAP_RE = re.compile(rb'(?m)^//# sourceMappingURL=main\.dart\.js\.map[ \t\r]*$')
_BOOTSTRAP_MAIN_JS_RE = re.compile(
    r'''(['"])mainJsPath\1(\s*:\s*)(['"])main\.dart\.js\3'''
)


def _prepare_bootstrap(web_dir: str, hashed_main: str) -> tuple[str, str | None]:
    """Validates flutter_bootstrap.js and returns (path, new_content or None if already set)."""
    bootstrap_path = os.path.join(web_dir, 'flutter_bootstrap.js')
    if not os.path.isfile(bootstrap_path):
        sys.exit(f'flutter_bootstrap.js not found in {web_dir}')
    with open(bootstrap_path, 'r', encoding='utf-8') as fh:
        content = fh.read()
    updated, count = _BOOTSTRAP_MAIN_JS_RE.subn(
        rf'\g<1>mainJsPath\g<1>\g<2>\g<3>{hashed_main}\g<3>',
        content,
    )
    if count == 0:
        if hashed_main in content:
            return (bootstrap_path, None)
        sys.exit(f'Could not locate mainJsPath="main.dart.js" in {bootstrap_path}')
    return (bootstrap_path, updated)


def fingerprint(web_dir: str) -> tuple[str, str] | None:
    """Fingerprints main.dart.js and returns (old_name, new_name), or None if already done."""
    if not os.path.isdir(web_dir):
        sys.exit(f'Build directory does not exist: {web_dir}')

    main_path = os.path.join(web_dir, 'main.dart.js')
    if not os.path.isfile(main_path):
        entries = os.listdir(web_dir)
        hashed = sorted(f for f in entries if _HASHED_MAIN.match(f))
        if len(hashed) == 1:
            expected_map = f'{hashed[0]}.map'
            orphan_map = os.path.join(web_dir, 'main.dart.js.map')
            if os.path.isfile(orphan_map):
                sys.exit(f'Found unhashed main.dart.js.map alongside {hashed[0]}')
            other_maps = [
                f for f in entries
                if f.endswith('.map') and _HASHED_MAIN_OR_MAP.match(f) and f != expected_map
            ]
            if other_maps:
                sys.exit(f'Found mismatched main map files alongside {hashed[0]}: {other_maps}')
            bootstrap_path, updated_bootstrap = _prepare_bootstrap(web_dir, hashed[0])
            if updated_bootstrap is not None:
                with open(bootstrap_path, 'w', encoding='utf-8', newline='') as fh:
                    fh.write(updated_bootstrap)
            return None
        if len(hashed) > 1:
            sys.exit(f'Multiple fingerprinted main bundles found in {web_dir}: {hashed}')
        sys.exit(f'main.dart.js not found in {web_dir}')

    with open(main_path, 'rb') as fh:
        raw = fh.read()

    digest = hashlib.sha256(raw).hexdigest()[:12]
    hashed_main = f'main.{digest}.dart.js'
    hashed_map = f'{hashed_main}.map'

    # Validate and prepare flutter_bootstrap.js before mutating any file on disk.
    bootstrap_path, updated_bootstrap = _prepare_bootstrap(web_dir, hashed_main)

    # Drop stale hashed artifacts from any uncleaned rebuild directory.
    for entry in os.listdir(web_dir):
        if _HASHED_MAIN_OR_MAP.match(entry) and entry not in (hashed_main, hashed_map):
            os.remove(os.path.join(web_dir, entry))

    map_path = os.path.join(web_dir, 'main.dart.js.map')
    has_map = os.path.isfile(map_path)
    if has_map:
        os.replace(map_path, os.path.join(web_dir, hashed_map))

    rewritten = (
        _SOURCE_MAP_RE.sub(f'//# sourceMappingURL={hashed_map}'.encode('utf-8'), raw)
        if has_map
        else raw
    )
    if rewritten != raw:
        with open(main_path, 'wb') as fh:
            fh.write(rewritten)

    os.replace(main_path, os.path.join(web_dir, hashed_main))
    if updated_bootstrap is not None:
        with open(bootstrap_path, 'w', encoding='utf-8', newline='') as fh:
            fh.write(updated_bootstrap)
    return ('main.dart.js', hashed_main)


if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'build/web'
    res = fingerprint(target)
    if res:
        print(f'{res[0]} -> {res[1]}')
    else:
        print('main web bundle already fingerprinted')
