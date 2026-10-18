import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/tokens.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import 'auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  final Map<String, String?> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool _validate() {
    final errors = <String, String?>{};
    if (_name.text.trim().length < 2) errors['name'] = 'Nama minimal 2 karakter.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      errors['email'] = 'Format email belum benar. Contoh: nama@contoh.com';
    }
    if (_password.text.length < 8) errors['password'] = 'Password minimal 8 karakter.';
    if (_confirm.text != _password.text) errors['confirm'] = 'Konfirmasi tidak sama dengan password.';
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.isEmpty;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).register(_name.text.trim(), _email.text.trim(), _password.text);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Buat akun lokal',
      subtitle: 'Password disimpan sebagai hash Argon2id dan hanya dipakai di perangkat ini.',
      showBack: true,
      children: [
        InlineError(_error),
        OnyxField(controller: _name, label: 'Nama', action: TextInputAction.next, error: _errors['name'], enabled: !_busy),
        const SizedBox(height: Sp.x4),
        OnyxField(
          controller: _email,
          label: 'Email',
          keyboard: TextInputType.emailAddress,
          action: TextInputAction.next,
          error: _errors['email'],
          enabled: !_busy,
        ),
        const SizedBox(height: Sp.x4),
        OnyxField(
          controller: _password,
          label: 'Password',
          obscure: true,
          action: TextInputAction.next,
          error: _errors['password'],
          helper: 'Minimal 8 karakter.',
          enabled: !_busy,
        ),
        const SizedBox(height: Sp.x4),
        OnyxField(
          controller: _confirm,
          label: 'Ulangi password',
          obscure: true,
          action: TextInputAction.done,
          error: _errors['confirm'],
          onSubmitted: (_) => _submit(),
          enabled: !_busy,
        ),
        const SizedBox(height: Sp.x6),
        OnyxButton(label: 'Buat akun', icon: FontAwesomeIcons.userPlus, expand: true, loading: _busy, onPressed: _submit),
      ],
    );
  }
}
