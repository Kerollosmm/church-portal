#!/usr/bin/env bash
# Installs Flutter (stable), firebase-tools and the FlutterFire CLI in Codespaces.
set -euo pipefail

if [ ! -d "$HOME/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$HOME/.pub-cache/bin:$PATH"

flutter config --no-analytics --enable-web
flutter precache --web
flutter --version

npm install -g firebase-tools
dart pub global activate flutterfire_cli

flutter pub get
(cd tool && npm install --no-audit --no-fund)

cat <<'MSG'

Ready. Useful commands:
  flutter test
  flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
  firebase login --no-localhost        # then: firebase deploy
MSG
