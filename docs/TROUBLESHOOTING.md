# Pemecahan masalah

| Gejala | Penyebab umum | Langkah |
| --- | --- | --- |
| Berkas tidak muncul di Penyimpanan internal | Izin semua berkas belum diberikan | Buka Berkas, tekan Beri izin, aktifkan "Izinkan akses semua berkas" |
| Terminal hanya punya perintah dasar | Busybox belum disertakan | Jalankan `scripts/fetch_busybox.sh` sebelum build |
| Font tampak berbeda | Font belum dibundel dan perangkat offline | Jalankan `scripts/fetch_fonts.sh` |
| SSH menolak koneksi setelah server dipasang ulang | Kunci host berubah | Server, menu profil, Lupakan sidik jari host |
| Koneksi SFTP habis waktu | Firewall atau proxy | Tes koneksi di profil, naikkan batas waktu di Lanjutan |
| Penyunting menolak berkas | Lebih dari 10 MB atau biner | Pakai penampil hex atau terminal |
| Video tidak mau diputar | Codec tidak didukung perangkat | Buka dengan aplikasi lain dari menu |
| `flutter analyze` mengeluh | Kode belum pernah dikompilasi pembuatnya | Perbaiki galat yang dilaporkan, lalu jalankan ulang |
| Transfer "Gagal" | Lihat pesan di kartu transfer | Coba lagi atau periksa izin tulis di tujuan |

## Analyze/Test gagal: IconData is final

font_awesome_flutter 10.x memperluas `IconData`, yang menjadi kelas final pada Flutter 3.41 ke atas. Workflow CI menyematkan Flutter 3.35.7. Naikkan versi itu hanya setelah font_awesome_flutter merilis versi yang kompatibel.
