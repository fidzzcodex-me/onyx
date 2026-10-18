import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';
import '../auth/pin_screen.dart';
import 'about_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final p = context.palette;
    final user = auth.user;
    return Scaffold(
      appBar: const OnyxAppBar(title: 'Pengaturan'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Sp.x12),
        children: [
          if (user != null)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
              child: Container(
                padding: const EdgeInsets.all(Sp.x4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: p.accentMuted,
                      child: Text(user.isGuest ? 'T' : user.initials, style: context.text.titleMedium?.copyWith(color: p.text)),
                    ),
                    const SizedBox(width: Sp.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.isGuest ? 'Tamu' : user.name, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(user.isGuest ? 'Data tersimpan di perangkat ini saja' : user.email, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    FaIcon(FontAwesomeIcons.chevronRight, size: 13, color: p.textMuted),
                  ],
                ),
              ),
            ),
          const SectionHeader('Tampilan'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
            child: Segmented<String>(
              options: const {'dark': 'Gelap', 'light': 'Terang', 'system': 'Sistem'},
              value: s.themeMode,
              onChanged: (v) => notifier.update((c) => c.copyWith(themeMode: v)),
            ),
          ),
          const SectionHeader('Terminal'),
          _SliderRow(
            title: 'Ukuran huruf',
            value: s.terminalFontSize,
            min: 10,
            max: 24,
            divisions: 14,
            label: '${s.terminalFontSize.round()}',
            onChanged: (v) => notifier.update((c) => c.copyWith(terminalFontSize: v)),
          ),
          NavRow(
            title: 'Shell',
            subtitle: switch (s.terminalShell) {
              'auto' => 'Otomatis: bash jika tersedia, jika tidak sh',
              final other => other,
            },
            icon: FontAwesomeIcons.terminal,
            onTap: () => showActionSheet(
              context,
              title: 'Shell bawaan',
              actions: [
                for (final shell in const ['auto', 'bash', 'sh'])
                  SheetAction(shell == 'auto' ? 'Otomatis' : shell, FontAwesomeIcons.terminal, () => notifier.update((c) => c.copyWith(terminalShell: shell))),
              ],
            ),
          ),
          SwitchRow(title: 'Bel perintah selesai', subtitle: 'Notifikasi saat perintah lama selesai dan aplikasi di latar', value: s.bellEnabled, onChanged: (v) => notifier.update((c) => c.copyWith(bellEnabled: v))),
          if (s.bellEnabled)
            _SliderRow(
              title: 'Ambang perintah lama',
              value: s.bellThresholdSec.toDouble(),
              min: 3,
              max: 120,
              divisions: 39,
              label: '${s.bellThresholdSec} detik',
              onChanged: (v) => notifier.update((c) => c.copyWith(bellThresholdSec: v.round())),
            ),
          SwitchRow(title: 'Jaga layar tetap menyala', subtitle: 'Hanya saat tab Terminal terbuka', value: s.keepScreenOnInTerminal, onChanged: (v) => notifier.update((c) => c.copyWith(keepScreenOnInTerminal: v))),
          const SectionHeader('Berkas'),
          SwitchRow(title: 'Tampilkan berkas tersembunyi', value: s.showHidden, onChanged: (v) => notifier.update((c) => c.copyWith(showHidden: v))),
          SwitchRow(title: 'Pakai sampah', subtitle: 'Hapus memindahkan ke sampah Onyx dulu', value: s.useTrash, onChanged: (v) => notifier.update((c) => c.copyWith(useTrash: v))),
          SwitchRow(title: 'Konfirmasi sebelum hapus', value: s.confirmDelete, onChanged: (v) => notifier.update((c) => c.copyWith(confirmDelete: v))),
          NavRow(
            title: 'Urutan',
            subtitle: '${const {'name': 'Nama', 'size': 'Ukuran', 'modified': 'Tanggal', 'type': 'Tipe'}[s.sort] ?? s.sort}, ${s.ascending ? 'naik' : 'turun'}',
            icon: FontAwesomeIcons.arrowDownWideShort,
            onTap: () => showActionSheet(
              context,
              title: 'Urutkan berkas',
              actions: [
                for (final e in const {'name': 'Nama', 'size': 'Ukuran', 'modified': 'Tanggal diubah', 'type': 'Tipe'}.entries)
                  SheetAction(e.value, FontAwesomeIcons.arrowDownWideShort, () => notifier.update((c) => c.copyWith(sort: e.key))),
                SheetAction(s.ascending ? 'Balik ke urutan turun' : 'Balik ke urutan naik', FontAwesomeIcons.arrowsUpDown, () => notifier.update((c) => c.copyWith(ascending: !c.ascending))),
              ],
            ),
          ),
          const SectionHeader('Penyunting'),
          _SliderRow(
            title: 'Ukuran huruf',
            value: s.editorFontSize,
            min: 10,
            max: 24,
            divisions: 14,
            label: '${s.editorFontSize.round()}',
            onChanged: (v) => notifier.update((c) => c.copyWith(editorFontSize: v)),
          ),
          SwitchRow(title: 'Bungkus baris', value: s.editorWrap, onChanged: (v) => notifier.update((c) => c.copyWith(editorWrap: v))),
          SwitchRow(title: 'Nomor baris', subtitle: 'Hanya tampil saat bungkus baris mati', value: s.editorLineNumbers, onChanged: (v) => notifier.update((c) => c.copyWith(editorLineNumbers: v))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
            child: Row(
              children: [
                Expanded(child: Text('Lebar tab', style: context.text.bodyMedium)),
                SizedBox(width: 168, child: Segmented<int>(options: const {2: '2', 4: '4', 8: '8'}, value: s.editorTabSize, onChanged: (v) => notifier.update((c) => c.copyWith(editorTabSize: v)))),
              ],
            ),
          ),
          SwitchRow(title: 'Cadangan saat simpan', subtitle: 'Menyimpan versi lama sebagai berkas dengan akhiran ~', value: s.editorBackup, onChanged: (v) => notifier.update((c) => c.copyWith(editorBackup: v))),
          const SectionHeader('Transfer'),
          _SliderRow(
            title: 'Transfer bersamaan',
            value: s.transferConcurrency.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            label: '${s.transferConcurrency}',
            onChanged: (v) => notifier.update((c) => c.copyWith(transferConcurrency: v.round())),
          ),
          NavRow(
            title: 'Folder unduhan',
            subtitle: s.downloadDir,
            icon: FontAwesomeIcons.download,
            onTap: () async {
              final value = await promptText(context, title: 'Folder unduhan', initial: s.downloadDir, confirmLabel: 'Simpan', validator: (v) => v.startsWith('/') ? null : 'Gunakan jalur absolut yang diawali /');
              if (value != null) notifier.update((c) => c.copyWith(downloadDir: value));
            },
          ),
          const SectionHeader('Keamanan'),
          NavRow(
            title: auth.hasPin ? 'Ubah PIN' : 'Atur PIN',
            subtitle: auth.hasPin ? 'PIN dipakai untuk membuka kunci aplikasi' : 'Kunci aplikasi dengan PIN 4 sampai 8 digit',
            icon: FontAwesomeIcons.lock,
            onTap: () => _setPin(context, ref),
          ),
          if (auth.hasPin)
            NavRow(
              title: 'Hapus PIN',
              icon: FontAwesomeIcons.lockOpen,
              danger: true,
              onTap: () => _clearPin(context, ref),
            ),
          if (auth.hasPin && auth.biometricAvailable)
            SwitchRow(
              title: 'Buka dengan biometrik',
              subtitle: 'Sidik jari atau wajah, PIN tetap tersedia',
              value: auth.biometricEnabled,
              onChanged: (v) => runGuarded(context, () => ref.read(authProvider.notifier).setBiometric(v)),
            ),
          if (auth.hasPin)
            NavRow(
              title: 'Kunci otomatis',
              subtitle: s.lockTimeoutSec == 0 ? 'Langsung saat aplikasi ke latar' : 'Setelah ${_timeoutLabel(s.lockTimeoutSec)} di latar',
              icon: FontAwesomeIcons.clock,
              onTap: () => showActionSheet(
                context,
                title: 'Kunci otomatis',
                actions: [
                  for (final sec in const [0, 15, 30, 60, 300, 900])
                    SheetAction(sec == 0 ? 'Langsung' : _timeoutLabel(sec), FontAwesomeIcons.clock, () => notifier.update((c) => c.copyWith(lockTimeoutSec: sec))),
                ],
              ),
            ),
          SwitchRow(
            title: 'Layar aman',
            subtitle: 'Blokir tangkapan layar dan pratinjau aplikasi terbaru',
            value: s.secureScreen,
            onChanged: (v) => notifier.update((c) => c.copyWith(secureScreen: v)),
          ),
          const SectionHeader('Lainnya'),
          NavRow(
            title: 'Tentang dan batasan',
            subtitle: 'Versi, lisensi, dan hal yang belum didukung',
            icon: FontAwesomeIcons.circleInfo,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
          ),
        ],
      ),
    );
  }

  static String _timeoutLabel(int sec) => sec < 60 ? '$sec detik' : '${sec ~/ 60} menit';

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    if (auth.hasPin) {
      final ok = await _verifyPin(context, ref);
      if (!ok || !context.mounted) return;
    }
    if (!context.mounted) return;
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PinSetupScreen()));
    if (done == true && context.mounted) toast(context, 'PIN disimpan');
  }

  Future<void> _clearPin(BuildContext context, WidgetRef ref) async {
    final ok = await _verifyPin(context, ref);
    if (!ok || !context.mounted) return;
    await runGuarded(context, () => ref.read(authProvider.notifier).clearPin(), success: 'PIN dihapus');
  }

  Future<bool> _verifyPin(BuildContext context, WidgetRef ref) async {
    final value = await promptText(
      context,
      title: 'Masukkan PIN saat ini',
      confirmLabel: 'Lanjut',
      obscure: true,
      keyboard: TextInputType.number,
      validator: (v) => RegExp(r'^\d{4,8}$').hasMatch(v) ? null : 'PIN terdiri dari 4 sampai 8 digit',
    );
    if (value == null || !context.mounted) return false;
    try {
      final result = await ref.read(apiProvider).auth.verifyPin(value);
      if (result.ok) return true;
      if (context.mounted) {
        toast(context, result.lockedMs > 0 ? 'Terlalu banyak percobaan. Coba lagi dalam ${(result.lockedMs / 1000).ceil()} detik.' : 'PIN salah. Sisa ${result.attemptsLeft} percobaan.', error: true);
      }
    } catch (error) {
      if (context.mounted) toast(context, OnyxError.from(error).message, error: true);
    }
    return false;
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.title, required this.value, required this.min, required this.max, required this.divisions, required this.label, required this.onChanged});

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: Text(title, style: context.text.bodyMedium)), Text(label, style: OnyxFonts.mono(size: 12, color: p.textSecondary))]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3, activeTrackColor: p.accent, inactiveTrackColor: p.surfaceAlt, thumbColor: p.accent, overlayColor: p.accent.withValues(alpha: 0.12)),
            child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
