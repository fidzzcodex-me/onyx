import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/tokens.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';
import 'reset_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _remember = true;
  bool _busy = false;
  String? _error;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate() {
    String? email;
    String? password;
    if (_email.text.trim().isEmpty) email = 'Email belum diisi. Masukkan alamat email untuk melanjutkan.';
    if (_password.text.isEmpty) password = 'Password belum diisi.';
    setState(() {
      _emailError = email;
      _passwordError = password;
    });
    return email == null && password == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_email.text.trim(), _password.text, _remember);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).guest();
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
      title: 'Masuk ke Onyx',
      subtitle: auth.hasAccounts
          ? 'Akun disimpan di perangkat ini dan tidak dikirim ke server mana pun.'
          : 'Belum ada akun di perangkat ini. Buat akun lokal atau lanjut sebagai tamu.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Belum punya akun?', style: context.text.bodySmall),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen())),
            child: const Text('Daftar'),
          ),
        ],
      ),
      children: [
        InlineError(_error),
        OnyxField(
          controller: _email,
          label: 'Email',
          hint: 'nama@contoh.com',
          keyboard: TextInputType.emailAddress,
          action: TextInputAction.next,
          error: _emailError,
          autofillHints: const [AutofillHints.email],
          enabled: !_busy,
        ),
        const SizedBox(height: Sp.x4),
        OnyxField(
          controller: _password,
          label: 'Password',
          obscure: true,
          action: TextInputAction.done,
          error: _passwordError,
          onSubmitted: (_) => _submit(),
          autofillHints: const [AutofillHints.password],
          enabled: !_busy,
        ),
        const SizedBox(height: Sp.x2),
        Row(
          children: [
            Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? true)),
            Expanded(child: Text('Ingat saya', style: context.text.bodySmall)),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ResetScreen())),
              child: const Text('Lupa password'),
            ),
          ],
        ),
        const SizedBox(height: Sp.x4),
        OnyxButton(label: 'Masuk', icon: FontAwesomeIcons.rightToBracket, expand: true, loading: _busy, onPressed: _submit),
        const SizedBox(height: Sp.x3),
        OnyxButton(label: 'Lanjut sebagai tamu', kind: OnyxButtonKind.secondary, expand: true, onPressed: _busy ? null : _guest),
      ],
    );
  }
}
