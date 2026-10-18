# Arsitektur

## Gambaran

```
+--------------------------------------------------------------+
|                         Flutter (Dart)                       |
|  screens/  ->  state/ (Riverpod)  ->  core/api.dart          |
|  widgets/, core/tokens.dart, core/theme.dart                 |
+------------------------------+-------------------------------+
                               | MethodChannel / EventChannel
                               | com.onyx.terminal/<nama>
+------------------------------v-------------------------------+
|                       Kotlin (android/)                      |
|  plugins/   satu plugin per channel                          |
|  auth/ security/ db/ terminal/ filesystem/ sftp/ editor/     |
|  viewer/ system/ service/                                    |
+------------------------------+-------------------------------+
                               | JNI
+------------------------------v-------------------------------+
|  C++ (pty.cpp, exec.cpp): forkpty, exec shell                |
+--------------------------------------------------------------+
```

## Alur data terminal

```
tombol/IME -> xterm Terminal.onOutput -> TermSession (Ctrl/Alt lengket)
          -> TerminalApi.write -> PtyManager -> PTY master fd
PTY master fd -> pembaca thread -> terminal_stream (bytes)
          -> TermSession (dekode UTF-8 bertahap) -> xterm Terminal.write
```

Keluaran terminal tidak pernah dianimasikan dan tidak melewati Riverpod per byte; hanya `TermSession` yang memegang buffer.

## Operasi latar berkas

Salin, pindah, cari, duplikat, ekstrak, dan kompres mengembalikan `opId` segera. Hasil dan progres datang lewat `fs_events` bertipe `op`. `FsApi.watchOp` dan `awaitOp` menyaring per id dan menyimpan event awal yang tiba sebelum pendengar dipasang.

## Navigasi dan tombol kembali

Navigator 1.0 dengan transisi fade dan geser 250ms. `ShellScreen` memegang lima tab dalam `IndexedStack` malas. Tombol kembali ditangani `PopScope(canPop: false)` yang bertanya ke `tabBackProvider`: setiap tab mendaftarkan fungsi yang mengembalikan `true` bila sudah menangani kembali (naik folder, tutup pencarian, batal seleksi). Bila tidak ada yang menangani, aplikasi dipindah ke latar.

## Penyimpanan

| Data | Tempat |
| --- | --- |
| Pengaturan | `settings.json` di direktori dukungan aplikasi, ditulis atomik |
| Akun, profil server, favorit, sampah | SQLite lewat `db/` |
| Password server, kunci privat | `CredentialStore` (Android Keystore, AES-GCM) |
| Password akun | Argon2id (BouncyCastle) |

## Desain

Token ada di satu berkas: `lib/core/tokens.dart` (`OnyxPalette`, `Sp`, `Rd`, `Motion`). Dua elemen khas, dijelaskan di IDENTITY.md: `CaretMark` (garis-bawah kursor penanda aktif) dan `PathRibbon` (pita jalur di app bar).

## Penyorot sintaks

`core/highlighter.dart`: pemindai regex per bahasa, satu lintasan, tanpa dependensi. `CodeController` menyimpan hasil per versi teks dan menumpuk sorotan hasil pencarian.
