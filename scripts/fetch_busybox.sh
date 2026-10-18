#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JNI="$ROOT/android/app/src/main/jniLibs"

ARM64_URL="${BUSYBOX_ARM64_URL:-}"
ARM_URL="${BUSYBOX_ARM_URL:-}"
X64_URL="${BUSYBOX_X86_64_URL:-}"

install_one() {
  local abi="$1"
  local url="$2"
  if [ -z "$url" ]; then
    echo "lewati $abi: variabel URL kosong"
    return 0
  fi
  mkdir -p "$JNI/$abi"
  curl -fsSL --retry 3 "$url" -o "$JNI/$abi/libbusybox.so"
  chmod 755 "$JNI/$abi/libbusybox.so"
  echo "terpasang: $abi"
}

install_one arm64-v8a "$ARM64_URL"
install_one armeabi-v7a "$ARM_URL"
install_one x86_64 "$X64_URL"

echo "Binary static busybox harus bernama libbusybox.so agar dapat dieksekusi dari nativeLibraryDir."
echo "Tanpa file ini Onyx memakai /system/bin/sh (toybox)."
