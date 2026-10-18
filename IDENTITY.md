# Identity Brief: Onyx

Jangkar desain. Setiap keputusan UI dicek ke file ini sebelum dikerjakan.

## Brand core
- Dikenal sebagai: satu alat untuk terminal, file, dan server di Android yang terasa ringan.
- Audiens + situasi mereka datang: developer dan admin server yang memegang ponsel saat di luar meja. Mereka ingin menjalankan perintah, memindahkan berkas, atau memeriksa server tanpa berpindah tiga aplikasi.
- Personality: presisi, tenang, teknis, cepat, tidak sok.
- TIDAK akan pernah terlihat/terdengar seperti: dasbor "AI" penuh neon, aplikasi file manager berwarna-warni, atau landing page SaaS dengan janji kosong.

## Visual territory
- Keywords: grafit, presisi, kursor, jalur, senyap, padat-tapi-bernapas.
- Warna:
  - Latar #121212 dan permukaan #1E1E1E membentuk tiga lapis abu netral. Hierarki dibuat oleh lapisan, bukan oleh bayangan.
  - Satu aksen biru #4A90E2 hanya untuk status aktif, fokus, dan aksi utama. Warna status (hijau, kuning, merah, cyan) hanya dipakai untuk arti statusnya.
  - Terminal memakai #0D0D0D agar terpisah dari kromium aplikasi.
  - Mode terang memakai #FAFAFA dengan aksen #1976D2, bukan hasil invert.
- Typography: Inter untuk antarmuka, JetBrains Mono untuk terminal, jalur, angka teknis. Skala: 28 / 22 / 18 / 15 / 13 / 11. Teks isi 15, metadata 13, tidak ada teks di bawah 11.
- Layout/bentuk: grid 4dp, spasi 4/8/12/16/24/32. Radius 10 kontrol, 12 kartu, 16 dialog, 20 sheet. Bar bawah 60dp, target sentuh minimal 48dp. Di tablet bar bawah menjadi rail samping.
- Imagery: tidak ada foto stok. Satu-satunya gambar merek adalah logo yang diunggah. Ilustrasi kosong-state memakai ikon Font Awesome satu keluarga (solid) di atas permukaan abu.

## Motion & voice
- Cara brand bergerak: pendek dan tegas. 250ms easeOutCubic untuk layar, 200ms easeOutBack untuk dialog, tekan tombol 0.97 selama 100ms. Keluaran terminal tidak pernah dianimasikan.
- Voice: bahasa Indonesia langsung, kalimat pendek, kata kerja di awal tombol ("Salin kunci", "Sambungkan", "Simpan"). Hindari seruan, janji, dan istilah pemasaran. Pesan galat selalu menyebut penyebab dan langkah berikutnya.

## Signature (maks 2)
- Elemen 1, Garis-bawah kursor: batang aksen pendek bergaya `_` dari logo menandai apa pun yang sedang aktif: tab navigasi, tab sesi terminal, baris terpilih, kolom yang fokus.
  - Lahir dari brand core karena: logo Onyx memuat prompt `>_`; kursor adalah bentuk paling jujur dari "alat kerja".
  - Dipakai di: bar navigasi, tab sesi, kolom input, pemilih. Komponen lain sengaja polos.
- Elemen 2, Pita jalur: setiap layar menaruh lokasi sekarang sebagai jalur monospace di app bar (cwd terminal, folder berkas, host:path remote, berkas yang dibuka).
  - Lahir dari brand core karena: produk ini menyatukan terminal dan berkas; keduanya berbagi satu cara menyebut posisi, yaitu jalur.
  - Dipakai di: Terminal, Berkas, SFTP, Penyunting, Penampil. Dasbor dan Pengaturan memakai judul biasa.

## Bukti yang BENAR-BENAR ada
- Boleh ditampilkan: nomor versi aplikasi, daftar fitur yang memang terpasang, batasan yang diketahui (halaman Tentang), nilai sistem nyata dari perangkat di dasbor.
- Belum ada (jadi placeholder bertanda): tautan repositori, kanal dukungan, kebijakan privasi publik. Tidak ada testimoni, jumlah pengguna, peringkat, atau logo klien.

## Penyimpangan yang disengaja
- Teks muted dinaikkan dari #7A7A7A ke #8C8C8C pada #121212 agar kontras tetap di atas 4.5:1 untuk teks 13px ke atas. Warna #7A7A7A hanya untuk ikon dekoratif.
- Aksen #4A90E2 pada #121212 memiliki kontras sekitar 5.6:1, cukup untuk teks. Pada latar terang dipakai #1976D2.

## Keputusan terbuka
- Nama berkas font diunduh lewat `scripts/fetch_fonts.sh` saat build; tanpa itu google_fonts mengunduh saat pertama jalan dan jatuh ke font sistem bila offline.
- Distribusi: izin akses semua berkas membuat aplikasi ini cocok untuk GitHub Releases atau F-Droid, bukan Play Store.

## Hasil audit sebelum rilis
- Tes buta: tanpa logo, ciri yang tersisa adalah pita jalur monospace di app bar, garis aksen pendek penanda aktif, dan tiga lapis abu netral tanpa bayangan.
- Tukar kompetitor: mengganti logo dan aksen pada aplikasi file manager lain tidak menghasilkan Onyx, karena pita jalur dan bahasa kata-kerja-di-depan tetap khas.
- Daftar slop: tidak ada gradien, glow, testimoni, angka pengguna palsu, atau emoji. Kartu hanya dipakai untuk satuan yang bisa diketuk atau berisi hasil.
- Belum diuji di perangkat nyata: kontras dan target sentuh dihitung dari token, bukan diukur pada layar.
