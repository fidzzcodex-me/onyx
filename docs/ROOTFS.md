# Onyx local rootfs (Alpine + proot)

Local shell seperti Termux. Ukuran base + rootfs boleh 80-100MB+.

## Komponen

1. proot sebagai `jniLibs/<abi>/libproot.so` (`scripts/fetch_proot.sh`)
2. Alpine minirootfs 3.20 diunduh ke `files/alpine/` saat bootstrap
3. `pkg` membungkus `apk` di dalam rootfs

## Perintah

```text
pkg update
pkg install curl git nodejs npm python3
pkg list
```

## Build proot

```bash
export PROOT_ARM64_URL='...'
export PROOT_ARM_URL='...'
export PROOT_X64_URL='...'
bash scripts/fetch_proot.sh
```

Tanpa proot, fallback ke shell Android.
