import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/tokens.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _name = TextEditingController(text: ref.read(authProvider).user?.name ?? '');
  late final TextEditingController _email = TextEditingController(text: ref.read(authProvider).user?.email ?? '');
  final TextEditingController _old = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _nameError;
  String? _emailError;
  String? _passError;
  bool _saving = false;
  bool _changing = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _old, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Nama belum diisi.' : null;
      _emailError = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ? null : 'Format email belum benar, contoh nama@contoh.com.';
    });
    if (_nameError != null || _emailError != null) return;
    setState(() => _saving = true);
    await runGuarded(context, () => ref.read(authProvider.notifier).updateProfile(name, email), success: 'Profil disimpan');
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _changePassword() async {
    if (_new.text.length < 8) {
      setState(() => _passError = 'Password baru minimal 8 karakter.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _passError = 'Konfirmasi password tidak sama.');
      return;
    }
    setState(() {
      _passError = null;
      _changing = true;
    });
    await runGuarded(context, () async {
      await ref.read(apiProvider).auth.changePassword(_old.text, _new.text);
      _old.clear();
      _new.clear();
      _confirm.clear();
    }, success: 'Password diganti');
    if (mounted) setState(() => _changing = false);
  }

  Future<void> _logout() async {
    final ok = await confirm(context, title: 'Keluar?', message: 'Anda perlu masuk lagi untuk membuka aplikasi. Berkas dan profil server tetap tersimpan.', confirmLabel: 'Keluar');
    if (!ok || !mounted) return;
    await ref.read(authProvider.notifier).logout();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Hapus akun?',
      message: 'Akun, profil server, kunci SSH, dan password tersimpan dihapus dari perangkat ini. Berkas di penyimpanan tidak dihapus. Tindakan ini tidak bisa dibatalkan.',
      confirmLabel: 'Hapus akun',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runGuarded(context, () => ref.read(authProvider.notifier).deleteAccount());
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final p = context.palette;
    if (user == null) return const Scaffold(body: SizedBox.shrink());
    return Scaffold(
      appBar: const OnyxAppBar(title: 'Profil'),
      body: ListView(
        padding: const EdgeInsets.all(Sp.x4),
        children: [
          if (user.isGuest) ...[
            OnyxCard(
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.userSecret, size: 18, color: p.textSecondary),
                  const SizedBox(width: Sp.x3),
                  Expanded(child: Text('Anda masuk sebagai tamu. Buat akun untuk mengunci aplikasi dengan password.', style: context.text.bodyMedium)),
                ],
              ),
            ),
            const SizedBox(height: Sp.x4),
            OnyxButton(label: 'Keluar dari mode tamu', icon: FontAwesomeIcons.rightFromBracket, kind: OnyxButtonKind.secondary, expand: true, onPressed: _logout),
          ] else ...[
            OnyxField(controller: _name, label: 'Nama', error: _nameError),
            const SizedBox(height: Sp.x3),
            OnyxField(controller: _email, label: 'Email', error: _emailError, keyboard: TextInputType.emailAddress),
            const SizedBox(height: Sp.x4),
            OnyxButton(label: 'Simpan profil', icon: FontAwesomeIcons.check, loading: _saving, expand: true, onPressed: _save),
            const SectionHeader('Ganti password', padding: EdgeInsets.fromLTRB(0, Sp.x8, 0, Sp.x2)),
            OnyxField(controller: _old, label: 'Password saat ini', obscure: true),
            const SizedBox(height: Sp.x3),
            OnyxField(controller: _new, label: 'Password baru', obscure: true, helper: 'Minimal 8 karakter'),
            const SizedBox(height: Sp.x3),
            OnyxField(controller: _confirm, label: 'Ulangi password baru', obscure: true, error: _passError),
            const SizedBox(height: Sp.x4),
            OnyxButton(label: 'Ganti password', kind: OnyxButtonKind.secondary, loading: _changing, expand: true, onPressed: _changePassword),
            const SectionHeader('Sesi', padding: EdgeInsets.fromLTRB(0, Sp.x8, 0, Sp.x2)),
            OnyxButton(label: 'Keluar', icon: FontAwesomeIcons.rightFromBracket, kind: OnyxButtonKind.secondary, expand: true, onPressed: _logout),
            const SizedBox(height: Sp.x3),
            OnyxButton(label: 'Hapus akun', icon: FontAwesomeIcons.trashCan, kind: OnyxButtonKind.danger, expand: true, onPressed: _delete),
          ],
        ],
      ),
    );
  }
}
