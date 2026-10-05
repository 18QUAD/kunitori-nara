#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  curl git unzip xz-utils zip libglu1-mesa libgtk-3-0

flutter_dir="/home/vscode/flutter"
if [ ! -x "$flutter_dir/bin/flutter" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION:-3.29.3}" \
    https://github.com/flutter/flutter.git "$flutter_dir"
fi
export PATH="$flutter_dir/bin:$PATH"
flutter config --enable-web
flutter precache --web
flutter pub get --enforce-lockfile
printf '\nReady: flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080\n'
