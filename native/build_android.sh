#!/usr/bin/env bash
# Builds libtradingcore.so for arm64-v8a into the Flutter project's jniLibs.
# Works in Termux (clang) or with an Android NDK (ANDROID_NDK_HOME set, e.g. in GitHub Actions).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/android/app/src/main/jniLibs/arm64-v8a"
SRC="$ROOT/native/cpp/engine/engine.cpp"
mkdir -p "$OUT"
FLAGS=(-std=c++20 -O2 -fPIC -shared -fvisibility=hidden -Wl,--gc-sections -Wl,-z,max-page-size=16384
       -Wl,-soname,libtradingcore.so -static-libstdc++)
if [ -n "${ANDROID_NDK_HOME:-}" ] && ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/aarch64-linux-android24-clang++ >/dev/null 2>&1; then
  CXX="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/aarch64-linux-android24-clang++ | head -1)"
  echo "Using NDK compiler: $CXX"
else
  CXX="${CXX:-clang++}"; echo "Using $CXX (Termux native)"
fi
"$CXX" "${FLAGS[@]}" -o "$OUT/libtradingcore.so" "$SRC"
# If the C++ runtime ended up dynamic, ship it next to our library.
RE="$(command -v llvm-readelf || command -v readelf || true)"
if [ -n "$RE" ] && "$RE" -d "$OUT/libtradingcore.so" | grep -q 'libc++_shared.so'; then
  LIBCXX="${PREFIX:-/data/data/com.termux/files/usr}/lib/libc++_shared.so"
  [ -f "$LIBCXX" ] || LIBCXX="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so | head -1)"
  cp "$LIBCXX" "$OUT/"; echo "Bundled libc++_shared.so"
fi
echo "Exported symbols: $( (nm -D "$OUT/libtradingcore.so" 2>/dev/null || true) | grep -c ' T engine_' )"
ls -l "$OUT"
