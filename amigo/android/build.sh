#!/usr/bin/env bash
# Собирает Амиго для Android: ../index.html → ../Amigo.apk (release, подписан ключом amigo-release.jks).
#
#   ./build.sh          — через Gradle + Android Gradle Plugin (как Android Studio)
#   ./build.sh --sdk    — напрямую инструментами Android SDK (aapt2, javac, d8, zipalign, apksigner):
#                         не нужен ни Gradle, ни интернет, только SDK
#
# Переменные окружения (необязательно):
#   ANDROID_HOME   — где лежит Android SDK (по умолчанию ищется сам: local.properties, /root/android-sdk, ~/Android/Sdk)
#   OUT            — куда положить APK (по умолчанию ../Amigo.apk)
#   GRADLE         — какой Gradle запускать (по умолчанию gradle из PATH, /opt/gradle/bin/gradle или ./gradlew)
#   GRADLE_FLAGS   — дополнительные флаги для Gradle, например "--offline"
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB="$(cd "$HERE/.." && pwd)"
OUT="${OUT:-$WEB/Amigo.apk}"
MODE=gradle
for arg in "$@"; do
  case "$arg" in
    --sdk) MODE=sdk ;;
    --gradle) MODE=gradle ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Неизвестный параметр: $arg (есть --sdk и --gradle)" >&2; exit 2 ;;
  esac
done

# Ключ подписи. Пароль простой и записан здесь нарочно — см. README.md.
KEYSTORE="$HERE/amigo-release.jks"
KEY_ALIAS=amigo
KEY_PASS=amigo123

die() { echo "ОШИБКА: $*" >&2; exit 1; }
step() { echo "==> $*"; }

[ -f "$WEB/index.html" ] || die "нет $WEB/index.html — сначала соберите веб-приложение: node tools/build.js"
[ -f "$KEYSTORE" ] || die "нет ключа $KEYSTORE (как сделать новый — в README.md)"
# index.html должен быть свежим: собран после последних правок в src/ и data/model.json
grep -q "AmigoAndroid" "$WEB/index.html" || die "index.html старый (нет поддержки AmigoAndroid) — пересоберите: node tools/build.js --no-train"
for f in "$WEB"/src/* "$WEB"/data/model.json; do
  [ "$f" -nt "$WEB/index.html" ] && die "$(basename "$f") новее index.html — сначала пересоберите: node tools/build.js --no-train"
done

# ---------- Android SDK
find_sdk() {
  local c
  for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
           "$(sed -n 's/^sdk\.dir=//p' "$HERE/local.properties" 2>/dev/null)" \
           /root/android-sdk "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [ -n "$c" ] && [ -d "$c/platforms" ]; then echo "$c"; return; fi
  done
}
SDK="$(find_sdk)"
[ -n "$SDK" ] || die "не найден Android SDK. Установите command-line tools и выполните:
  sdkmanager \"platforms;android-34\" \"build-tools;35.0.0\"   и задайте ANDROID_HOME"
export ANDROID_HOME="$SDK"

# ---------- версии берём из app/build.gradle, чтобы они были записаны в одном месте
gradle_value() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=?[[:space:]]*'?([^' ]+)'?.*/\1/p" "$HERE/app/build.gradle" | head -1; }
APP_ID="$(gradle_value applicationId)"
VERSION_CODE="$(gradle_value versionCode)"
VERSION_NAME="$(gradle_value versionName)"
MIN_SDK="$(gradle_value minSdk)"
TARGET_SDK="$(gradle_value targetSdk)"
COMPILE_SDK="$(gradle_value compileSdk)"

BT="$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sed 's:/$::' | sort -V | tail -1)"
[ -n "$BT" ] && [ -x "$BT/apksigner" ] || die "в $SDK нет build-tools: sdkmanager \"build-tools;35.0.0\""
PLATFORM_JAR="$SDK/platforms/android-$COMPILE_SDK/android.jar"
[ -f "$PLATFORM_JAR" ] || die "нет $PLATFORM_JAR: sdkmanager \"platforms;android-$COMPILE_SDK\""

# ---------- что из веб-приложения кладём в APK (assets/)
# sw.js нарочно не кладём: в APK всё и так офлайн, а service worker с кэшем
# мог бы показывать старую версию после обновления приложения.
copy_web_assets() {
  local dst="$1" f
  mkdir -p "$dst"
  cp "$WEB/index.html" "$dst/"
  [ -f "$WEB/manifest.webmanifest" ] && cp "$WEB/manifest.webmanifest" "$dst/"
  if [ -d "$WEB/icons" ]; then
    mkdir -p "$dst/icons"
    for f in "$WEB"/icons/*.png "$WEB"/icons/*.svg; do [ -f "$f" ] && cp "$f" "$dst/icons/"; done
  fi
  return 0
}

build_gradle() {
  local g="${GRADLE:-}"
  if [ -z "$g" ]; then
    if command -v gradle >/dev/null 2>&1; then g=gradle
    elif [ -x /opt/gradle/bin/gradle ]; then g=/opt/gradle/bin/gradle
    else g="$HERE/gradlew"; fi
  fi
  step "Gradle ($g): assembleRelease"
  # assets копирует сама сборка (задача copyWebAssets в app/build.gradle)
  # shellcheck disable=SC2086
  if ! "$g" -p "$HERE" --console=plain ${GRADLE_FLAGS:-} assembleRelease; then
    die "Gradle не справился. Можно собрать без Gradle: ./build.sh --sdk"
  fi
  cp "$HERE/app/build/outputs/apk/release/app-release.apk" "$OUT"
}

build_sdk() {
  local W="$HERE/build/sdk" classes dexed
  rm -rf "$W"
  mkdir -p "$W/gen" "$W/classes" "$W/dex"
  step "assets: index.html и иконки"
  copy_web_assets "$W/assets"

  step "aapt2: ресурсы и манифест (build-tools $(basename "$BT"), android-$COMPILE_SDK)"
  sed "s|<manifest |<manifest package=\"$APP_ID\" |" "$HERE/app/src/main/AndroidManifest.xml" > "$W/AndroidManifest.xml"
  "$BT/aapt2" compile --dir "$HERE/app/src/main/res" -o "$W/res.zip"
  "$BT/aapt2" link -o "$W/unsigned.apk" -I "$PLATFORM_JAR" \
    --manifest "$W/AndroidManifest.xml" \
    --min-sdk-version "$MIN_SDK" --target-sdk-version "$TARGET_SDK" \
    --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
    -A "$W/assets" --java "$W/gen" "$W/res.zip"

  step "javac + d8"
  mapfile -t sources < <(find "$HERE/app/src/main/java" "$W/gen" -name '*.java')
  javac -J-Duser.language=en -source 8 -target 8 -encoding UTF-8 -Xlint:all -Xlint:-options \
    -bootclasspath "$PLATFORM_JAR:$BT/core-lambda-stubs.jar" -d "$W/classes" "${sources[@]}"
  mapfile -t classes < <(find "$W/classes" -name '*.class')
  "$BT/d8" --release --min-api "$MIN_SDK" --lib "$PLATFORM_JAR" --output "$W/dex" "${classes[@]}"
  (cd "$W/dex" && zip -q -X "$W/unsigned.apk" classes.dex)

  step "zipalign + apksigner"
  "$BT/zipalign" -p -f 4 "$W/unsigned.apk" "$W/aligned.apk"
  "$BT/apksigner" sign --ks "$KEYSTORE" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass "pass:$KEY_PASS" --key-pass "pass:$KEY_PASS" --out "$OUT" "$W/aligned.apk"
  rm -f "$OUT.idsig"
}

if [ "$MODE" = sdk ]; then build_sdk; else build_gradle; fi

step "проверка"
"$BT/apksigner" verify "$OUT" || die "подпись не прошла проверку"
"$BT/aapt2" dump badging "$OUT" 2>/dev/null | grep -E "^(package|minSdkVersion|targetSdkVersion|uses-permission|application-label):" || true
echo
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1), версия $VERSION_NAME, код $VERSION_CODE)"
