# Onyx

Terminal, berkas, dan server dalam satu aplikasi Android. Backend native Kotlin, antarmuka Flutter. Paket `com.onyx.terminal`, Android 8.0 sampai 15.

> Status jujur: kode ini ditulis tanpa bisa dikompilasi di lingkungan pembuatnya (SDK Flutter dan Android diblokir). Jalankan `flutter analyze` dan build di mesin Anda atau lewat GitHub Actions, lalu perbaiki galat kompilasi kecil yang mungkin muncul. Lihat [Batasan](#batasan-yang-diketahui).

## Fitur

| Area | Isi |
| --- | --- |
| Akses | Registrasi dan login lokal (Argon2id), mode tamu, PIN, biometrik, kunci otomatis, layar aman |
| Dasbor | CPU, RAM, penyimpanan, baterai, jaringan dengan sparkline, info perangkat |
| Terminal | Shell lokal berbasis PTY (JNI), banyak tab, bilah tombol tambahan, Ctrl/Alt lengket, sesi SSH, bel perintah selesai |
| Berkas | Jelajah, salin/pindah dengan progres, sampah, cari (regex), duplikat, properti dan chmod, checksum, favorit, ZIP/TAR/7z/RAR/GZ/BZ2/XZ |
| Server | SFTP, SCP, FTP, FTPS, WebDAV, proxy HTTP/SOCKS5, jump host, kunci SSH (Ed25519, ECDSA, RSA), antrean transfer, sinkron folder |
| Penyunting | Deteksi penyandian, akhir baris, BOM, cari dan ganti (regex), undo, indentasi otomatis, simpan atomik, deteksi konflik, edit berkas remote |
| Penampil | Gambar, video, audio, PDF, arsip, hex, JSON, CSV |
| Alat | Ping TCP, DNS, pindai port, permintaan HTTP, IP publik, proses, log |

## Struktur

```
lib/            antarmuka Flutter (Riverpod, Navigator 1.0)
android/        backend Kotlin, JNI/CMake untuk PTY
assets/         logo, shell rc, konfigurasi bawaan
scripts/        pembantu build dan pemeriksa kode
test/           tes Dart
.github/        build dan rilis
```

Rincian ada di [ARCHITECTURE.md](ARCHITECTURE.md) dan [API.md](API.md). Panduan desain ada di [IDENTITY.md](IDENTITY.md).

## Membangun

Prasyarat: Flutter 3.27 atau lebih baru (Dart 3.6), JDK 17, Android SDK 35, NDK dan CMake dari SDK Manager.

```
bash scripts/fetch_fonts.sh
bash scripts/fetch_busybox.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Tes Kotlin: `cd android && ./gradlew testDebugUnitTest`.

Tanpa `fetch_fonts.sh`, `google_fonts` mengunduh font saat pertama jalan dan memakai font sistem bila offline. Tanpa `fetch_busybox.sh`, aplikasi tetap berjalan tetapi hanya dengan perintah bawaan Android.

Build di GitHub Actions: `.github/workflows/build.yml` (analisis, tes, APK debug dan rilis) dan `release.yml` (tag `v*`). Penandatanganan ada di [docs/SIGNING.md](docs/SIGNING.md).

## Aturan kode

- Tidak ada komentar `//` atau `/* */`. Diperiksa oleh `python3 scripts/check_no_comments.py` dan CI.
- Tanpa emoji. Ikon hanya Font Awesome.
- Semua warna, jarak, radius, dan durasi berasal dari `lib/core/tokens.dart`.

## Batasan yang diketahui

- Belum pernah dikompilasi oleh pembuatnya. Anggap build pertama sebagai tahap perbaikan.
- Izin akses semua berkas membuatnya cocok untuk GitHub Releases atau F-Droid, bukan Google Play.
- Busybox dimuat lewat trik `jniLibs`; tidak semua perintah GNU tersedia.
- Tidak ada penerusan agen SSH. Kunci host dipercaya saat pertama kali (TOFU).
- Tidak ada pohon SAF; penyimpanan lewat jalur berkas.
- RAR hanya ekstrak. ZIP bersandi belum didukung.
- Proxy HTTP/SOCKS5 hanya untuk SSH/SFTP/SCP. SCP tidak bisa dilanjutkan.
- Penampil PDF tanpa pencarian teks. Pemasangan font hanya pratinjau.
- Statistik CPU memakai `/proc/stat`, lalu `cpufreq` sebagai cadangan. Daftar proses dibatasi UID yang sama.
- Ping memakai TCP, bukan ICMP. Tidak ada traceroute.
- Penyunting menolak berkas di atas 10 MB. Penyorotan sintaks mati di atas 160 ribu karakter. Nomor baris hanya tampil saat bungkus baris mati.

## Lisensi

MIT. Lihat [LICENSE](LICENSE).
