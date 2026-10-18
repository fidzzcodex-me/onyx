import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../widgets/common.dart';

const _limitations = <(String, String)>[
  ('Distribusi', 'Izin akses semua berkas membuat aplikasi ini cocok untuk GitHub Releases atau F-Droid, bukan Google Play.'),
  ('Busybox', 'Perintah tambahan dimuat dari pustaka bawaan APK. Beberapa perintah GNU tidak tersedia.'),
  ('Kunci host SSH', 'Kunci host dipercaya saat pertama kali (TOFU). Tidak ada penerusan agen SSH.'),
  ('SCP', 'Tidak mendukung melanjutkan transfer yang terputus.'),
  ('Proxy', 'Proxy HTTP dan SOCKS5 hanya untuk SSH, SFTP, dan SCP.'),
  ('Pohon SAF', 'Penyimpanan hanya lewat jalur berkas. Folder yang diberikan lewat Storage Access Framework tidak didukung.'),
  ('Arsip', 'RAR hanya bisa diekstrak. ZIP bersandi belum didukung.'),
  ('PDF', 'Penampil PDF tidak punya pencarian teks.'),
  ('Font', 'Pemasangan font hanya berupa pratinjau.'),
  ('Proses', 'Android membatasi daftar proses ke aplikasi ini. Sinyal hanya bisa dikirim ke proses milik Onyx.'),
  ('CPU', 'Statistik CPU memakai /proc/stat, lalu cpufreq bila /proc/stat ditolak sistem.'),
  ('Ping', 'Ping memakai sambungan TCP, bukan ICMP. Traceroute belum tersedia.'),
  ('Berkas besar', 'Penyunting menolak berkas di atas 10 MB. Penyorotan sintaks dimatikan di atas 160 ribu karakter.'),
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: const OnyxAppBar(title: 'Tentang'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, Sp.x12),
        children: [
          Center(child: Column(children: [const OnyxLogo(size: 88), const SizedBox(height: Sp.x3), Text('Onyx', style: context.text.headlineSmall), Text('Versi 1.0.0', style: OnyxFonts.mono(size: 12, color: p.textSecondary))])),
          const SizedBox(height: Sp.x6),
          OnyxCard(
            child: Text(
              'Terminal, berkas, dan server dalam satu aplikasi Android. Semua berjalan di perangkat Anda. Onyx tidak mengirim data apa pun ke server kami.',
              style: context.text.bodyMedium,
            ),
          ),
          const SectionHeader('Batasan yang diketahui', padding: EdgeInsets.fromLTRB(0, Sp.x6, 0, Sp.x2)),
          for (final item in _limitations)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.x2),
              child: OnyxCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.$1, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text(item.$2, style: context.text.bodyMedium?.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
            ),
          const SectionHeader('Lisensi', padding: EdgeInsets.fromLTRB(0, Sp.x6, 0, Sp.x2)),
          OnyxButton(
            label: 'Lisensi sumber terbuka',
            icon: FontAwesomeIcons.scaleBalanced,
            kind: OnyxButtonKind.secondary,
            expand: true,
            onPressed: () => showLicensePage(context: context, applicationName: 'Onyx', applicationVersion: '1.0.0'),
          ),
        ],
      ),
    );
  }
}
