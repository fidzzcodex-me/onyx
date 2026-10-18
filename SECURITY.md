# Keamanan

Laporkan kerentanan secara privat lewat fitur pelaporan keamanan repositori. Jangan membuka isu publik berisi detail eksploit. Kanal kontak resmi belum ditetapkan; isi bagian ini sebelum rilis publik.

## Model ancaman singkat

- Data tersimpan hanya di perangkat. Tidak ada telemetri.
- Password akun disimpan sebagai hash Argon2id. Password server dan kunci privat dienkripsi dengan kunci Android Keystore.
- Kunci host SSH dipercaya saat pertama kali. Jika kunci berubah, koneksi ditolak sampai pengguna memilih "Lupakan sidik jari host".
- Ekstraksi arsip menolak jalur di luar folder tujuan (`zip_slip`).
- `FLAG_SECURE` dapat diaktifkan dari Pengaturan untuk memblokir tangkapan layar.
- FTP polos tidak terenkripsi; antarmuka memperingatkan hal ini.

## Di luar cakupan

Perangkat yang di-root atau sudah terinfeksi, dan akses fisik ke perangkat yang tidak terkunci.
