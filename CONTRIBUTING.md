# Berkontribusi

1. Fork dan buat cabang dari `main`.
2. Jalankan sebelum commit:
   ```
   python3 scripts/check_no_comments.py
   python3 scripts/check_dart_refs.py
   flutter analyze
   flutter test
   ```
3. Aturan wajib: tanpa komentar `//` dan `/* */`, tanpa emoji, ikon Font Awesome saja, warna dan jarak dari `tokens.dart`, teks antarmuka berbahasa Indonesia dengan kata kerja di awal tombol, pesan galat menyebut penyebab dan langkah berikutnya.
4. Setiap channel baru ditambahkan di tiga tempat: `Channels` (Kotlin), plugin, dan `api.dart`. Perbarui `API.md`.
5. Perubahan tampilan dicek ke IDENTITY.md. Elemen khas maksimal dua; jangan menambah yang ketiga.
6. Tes untuk logika murni (parser, format, penyorot, arsip).
