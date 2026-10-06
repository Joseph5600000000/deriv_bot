#!/usr/bin/env bash
# Usage (from the unzipped kit folder):  bash tools/setup_project.sh [target_dir]
# Creates the Flutter Android project and overlays our code on top of it.
set -euo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HOME/deriv_bot_app}"
command -v flutter >/dev/null || { echo "flutter not on PATH (see docs/BUILD_GUIDE.md)"; exit 1; }
if [ ! -d "$DEST/android" ]; then
  flutter create --project-name deriv_bot --org com.example --platforms android "$DEST"
fi
rm -rf "$DEST/lib" "$DEST/test"
cp -r "$KIT/lib" "$KIT/native" "$KIT/tools" "$KIT/assets" "$DEST/"
mkdir -p "$DEST/test"; cp "$KIT/test/dart/"*.dart "$DEST/test/" 2>/dev/null || true
cp "$KIT/pubspec.yaml" "$KIT/analysis_options.yaml" "$DEST/"
cp -r "$KIT/android_overlay/res/." "$DEST/android/app/src/main/res/"
# Stale v1/v2 vector icon would shadow the new PNG foreground (unzip -o never deletes old files). Remove AFTER the copy.
rm -f "$DEST/android/app/src/main/res/drawable/ic_launcher_foreground.xml"
# Release builds need INTERNET in the MAIN manifest (the template only adds it for debug/profile).
M="$DEST/android/app/src/main/AndroidManifest.xml"
grep -q 'android.permission.INTERNET' "$M" || sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$M"
sed -i 's#android:label="[^"]*"#android:label="DeltaDesk"#' "$M"
python3 "$DEST/tools/gen_structs.py"
bash "$DEST/native/build_android.sh"
echo "Project ready in $DEST. Next: cd $DEST && flutter pub get && flutter build apk --release --target-platform android-arm64"
