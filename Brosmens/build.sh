#!/usr/bin/env bash
# Сборка APK «Бросменс»: ./build.sh  →  dist/Brosmens.apk
set -euo pipefail
cd "$(dirname "$0")"
export ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk}
if [ ! -f web/vendor/anthropic.mjs ] || [ ! -f web/vendor/three.module.js ] || [ ! -f web/vendor/peerjs.mjs ]; then
  (cd tools && npm install --silent && cp node_modules/three/build/three.module.js ../web/vendor/ \
    && npx esbuild anthropic-entry.js --bundle --format=esm --platform=browser --minify --outfile=../web/vendor/anthropic.mjs \
    && npx esbuild peerjs-entry.js --bundle --format=esm --platform=browser --minify --outfile=../web/vendor/peerjs.mjs)
fi
echo "sdk.dir=$ANDROID_HOME" > android/local.properties
(cd android && ${GRADLE:-gradle} --no-daemon -q assembleRelease)
mkdir -p dist && cp android/app/build/outputs/apk/release/app-release.apk dist/Brosmens.apk
ls -la dist/Brosmens.apk
