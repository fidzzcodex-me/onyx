#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JNI="$ROOT/android/app/src/main/jniLibs"
mkdir -p "$JNI"/{arm64-v8a,armeabi-v7a,x86_64}

echo "Onyx: fetch proot static binaries for Android"
echo "Set PROOT_ARM64_URL PROOT_ARM_URL PROOT_X64_URL to direct binary URLs."
echo "Place as: jniLibs/<abi>/libproot.so"

install_one() {
  local abi="$1" url="$2"
  if [ -z "$url" ]; then
    echo "skip $abi (no URL)"
    return 0
  fi
  mkdir -p "$JNI/$abi"
  curl -fsSL --retry 3 "$url" -o "$JNI/$abi/libproot.so"
  chmod 755 "$JNI/$abi/libproot.so"
  echo "ok $abi ($(wc -c < "$JNI/$abi/libproot.so") bytes)"
}

install_one arm64-v8a "${PROOT_ARM64_URL:-}"
install_one armeabi-v7a "${PROOT_ARM_URL:-}"
install_one x86_64 "${PROOT_X64_URL:-}"
