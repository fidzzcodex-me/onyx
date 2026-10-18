# Kontrak channel Flutter ke Kotlin

Semua nama channel berbentuk `com.onyx.terminal/<nama>`. Sumber kebenaran: `lib/core/api.dart` (sisi Dart) dan `util/Constants.kt` objek `Channels` (sisi Kotlin). Galat native dikirim sebagai `PlatformException` dengan `code` dan pesan Indonesia; Dart membungkusnya menjadi `OnyxError`.

| Channel | Jenis | Dipakai untuk |
| --- | --- | --- |
| `auth` | Method | Akun, PIN, biometrik |
| `terminal` | Method | Mulai/tutup sesi, tulis, ubah ukuran |
| `terminal_stream` | Event | `data`, `exit`, `title`, `cwd`, `bell`, `commandFinished` |
| `fs` | Method | Daftar, salin, pindah, sampah, cari, arsip, bookmark |
| `fs_events` | Event | `op` (progres operasi latar), `change` (folder berubah) |
| `sftp` | Method | Profil, koneksi, daftar jauh, transfer, sinkron, kunci SSH |
| `sftp_stream` | Event | `transfer` (satu item), `queue` (perubahan antrean) |
| `editor` | Method | `read`, `write`, `language`, `encodings` |
| `viewer` | Method | Info media, halaman PDF, hex, JSON, CSV |
| `window` | Method | `setSecure`, `setKeepScreenOn`, `moveToBack` |
| `system` | Method | Info perangkat, snapshot, DNS, ping, pindai port, HTTP, log |
| `system_stream` | Event | `snapshot`, `scan` |
| `process` | Method | Daftar proses, kirim sinyal |

## Event `op`

```
{ type: "op", id, kind, state: running|done|error|canceled, done, total, current, ...hasil }
```

`kind`: `copy`, `move`, `search`, `duplicates`, `extract`, `compress`. Hasil pencarian ada di `results`, duplikat di `groups`.

## Konflik penyimpanan editor

`editor.write` menerima `expectedModified`. Bila berkas berubah lebih dari 1 detik sejak dibaca, native melempar kode `conflict` dan UI menawarkan timpa atau muat ulang.

## Kode galat umum

`bad_args`, `not_found`, `denied`, `too_large`, `binary`, `conflict`, `zip_slip`, `no_session`, `secret_missing`, `forbidden`, `unavailable`.
