#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JNI="$ROOT/android/app/src/main/jniLibs"

PROOT_ARM64_URL="${PROOT_ARM64_URL:-https://skirsten.github.io/proot-portable-android-binaries/aarch64/proot}"
PROOT_ARM_URL="${PROOT_ARM_URL:-https://skirsten.github.io/proot-portable-android-binaries/armv7/proot}"
PROOT_X64_URL="${PROOT_X64_URL:-https://skirsten.github.io/proot-portable-android-binaries/x86_64/proot}"

install_one() {
  local abi="$1" url="$2"
  mkdir -p "$JNI/$abi"
  echo "fetch proot -> $abi"
  curl -fsSL --retry 3 "$url" -o "$JNI/$abi/libproot.so"
  chmod 755 "$JNI/$abi/libproot.so"
  echo "ok $abi ($(wc -c < "$JNI/$abi/libproot.so") bytes)"
}

install_one arm64-v8a "$PROOT_ARM64_URL"
install_one armeabi-v7a "$PROOT_ARM_URL"
install_one x86_64 "$PROOT_X64_URL"
echo "proot ready under jniLibs"
