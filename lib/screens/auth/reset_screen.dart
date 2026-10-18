import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/tokens.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';
import 'auth_widgets.dart';

class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key});

  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  bool _verified = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _verifyPin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiProvider).auth.verifyPin(_pin.text.trim());
      if (result.ok) {
        setState(() => _verified = true);
      } else if (result.lockedMs > 0) {
        setState(() => _error = 'Terlalu banyak percobaan. Coba lagi dalam ${(result.lockedMs / 1000).ceil()} detik.');
      } else {
        setState(() => _error = 'PIN salah. Sisa percobaan: ${result.attemptsLeft}.');
      }
    } catch (error) {
      setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyBiometric() async {
    final ok = await ref.read(authProvider.notifier).unlockWithBiometric();
    if (!mounted) return;
    if (ok) {
      setState(() => _verified = true);
    } else {
      setState(() => _error = 'Verifikasi biometrik dibatalkan atau gagal.');
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty || _password.text.length < 8) {
      setState(() => _error = 'Isi email akun dan password baru minimal 8 karakter.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).auth.resetPassword(_email.text.trim(), _password.text);
      if (!mounted) return;
      toast(context, 'Password diganti. Silakan masuk.');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return AuthScaffold(
      title: 'Atur ulang password',
      subtitle: auth.hasPin
          ? 'Tidak ada pengiriman email. Verifikasi dulu dengan PIN atau biometrik perangkat ini.'
          : 'Pengaturan ulang membutuhkan PIN atau biometrik. PIN belum dibuat di perangkat ini, jadi password tidak dapat diatur ulang.',
      showBack: true,
      children: [
        InlineError(_error),
        if (!_verified && auth.hasPin) ...[
          OnyxField(
            controller: _pin,
            label: 'PIN',
            obscure: true,
            keyboard: TextInputType.number,
            action: TextInputAction.done,
            onSubmitted: (_) => _verifyPin(),
          ),
          const SizedBox(height: Sp.x4),
          OnyxButton(label: 'Verifikasi PIN', expand: true, loading: _busy, onPressed: _verifyPin),
          if (auth.biometricEnabled) ...[
            const SizedBox(height: Sp.x3),
            OnyxButton(
              label: 'Gunakan biometrik',
              icon: FontAwesomeIcons.fingerprint,
              kind: OnyxButtonKind.secondary,
              expand: true,
              onPressed: _verifyBiometric,
            ),
          ],
        ],
        if (_verified) ...[
          OnyxField(controller: _email, label: 'Email akun', keyboard: TextInputType.emailAddress, action: TextInputAction.next),
          const SizedBox(height: Sp.x4),
          OnyxField(controller: _password, label: 'Password baru', obscure: true, helper: 'Minimal 8 karakter.', action: TextInputAction.done, onSubmitted: (_) => _reset()),
          const SizedBox(height: Sp.x6),
          OnyxButton(label: 'Simpan password baru', icon: FontAwesomeIcons.key, expand: true, loading: _busy, onPressed: _reset),
        ],
      ],
    );
  }
}
