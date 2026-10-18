import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/tokens.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.length, required this.max, required this.onDigit, required this.onBackspace, this.onSubmit, this.trailing, this.enabled = true});

  final int length;
  final int max;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onSubmit;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget key(Widget child, VoidCallback? onTap, {String? label}) {
      return Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 40,
          child: Container(
            height: 64,
            margin: const EdgeInsets.all(Sp.x1),
            decoration: BoxDecoration(color: p.surface, borderRadius: Rd.d, border: Border.all(color: p.border)),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
    }

    Widget digit(int n) => key(
          Text('$n', style: OnyxDigitStyle.of(context)),
          () {
            HapticFeedback.selectionClick();
            onDigit(n);
          },
          label: '$n',
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < max; i++)
              AnimatedContainer(
                duration: Motion.dialog,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < length ? p.accent : Colors.transparent,
                  border: Border.all(color: i < length ? p.accent : p.textMuted, width: 1.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: Sp.x8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            children: [
              for (final row in const [
                [1, 2, 3],
                [4, 5, 6],
                [7, 8, 9]
              ])
                Row(children: [for (final n in row) Expanded(child: digit(n))]),
              Row(
                children: [
                  Expanded(
                    child: trailing == null
                        ? const SizedBox(height: 64)
                        : key(trailing!, null, label: 'Biometrik'),
                  ),
                  Expanded(child: digit(0)),
                  Expanded(child: key(FaIcon(FontAwesomeIcons.deleteLeft, size: 20, color: p.textSecondary), onBackspace, label: 'Hapus')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class OnyxDigitStyle {
  static TextStyle of(BuildContext context) => context.text.headlineSmall!.copyWith(fontWeight: FontWeight.w500);
}

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  String _pin = '';
  String? _message;
  bool _busy = false;
  Timer? _timer;
  int _lockedSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authProvider).biometricEnabled) _biometric();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _biometric() async {
    final ok = await ref.read(authProvider.notifier).unlockWithBiometric();
    if (!ok && mounted) setState(() => _message = 'Biometrik tidak dikenali. Masukkan PIN.');
  }

  void _startLock(int ms) {
    _timer?.cancel();
    setState(() => _lockedSeconds = (ms / 1000).ceil());
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _lockedSeconds = (_lockedSeconds - 1).clamp(0, 1 << 30));
      if (_lockedSeconds == 0) {
        t.cancel();
        setState(() => _message = null);
      }
    });
  }

  Future<void> _add(int digit) async {
    if (_busy || _lockedSeconds > 0 || _pin.length >= 6) return;
    setState(() => _pin += '$digit');
    if (_pin.length == 6) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      _verify();
    }
  }

  Future<void> _verify() async {
    if (_busy || _pin.length < 4) return;
    setState(() => _busy = true);
    final outcome = await ref.read(authProvider.notifier).unlockWithPin(_pin);
    if (!mounted) return;
    if (outcome.ok) return;
    HapticFeedback.heavyImpact();
    if (outcome.error != null) {
      setState(() {
        _busy = false;
        _pin = '';
        _message = outcome.error;
      });
      return;
    }
    if (outcome.lockedMs > 0) {
      setState(() {
        _busy = false;
        _pin = '';
        _message = 'Terlalu banyak percobaan.';
      });
      _startLock(outcome.lockedMs);
      return;
    }
    setState(() {
      _busy = false;
      _pin = '';
      _message = 'PIN salah. Sisa percobaan: ${outcome.attemptsLeft}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OnyxLogo(size: 64),
                const SizedBox(height: Sp.x6),
                Text('Masukkan PIN', style: context.text.headlineSmall),
                const SizedBox(height: Sp.x2),
                SizedBox(
                  height: 40,
                  child: Text(
                    _lockedSeconds > 0 ? 'Terkunci. Coba lagi dalam $_lockedSeconds detik.' : (_message ?? '4 sampai 6 digit'),
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(color: _message != null || _lockedSeconds > 0 ? p.error : p.textSecondary),
                  ),
                ),
                const SizedBox(height: Sp.x4),
                PinPad(
                  length: _pin.length,
                  max: 6,
                  enabled: !_busy && _lockedSeconds == 0,
                  onDigit: _add,
                  onBackspace: () {
                    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                  },
                  trailing: auth.biometricEnabled
                      ? GestureDetector(
                          onTap: _biometric,
                          child: FaIcon(FontAwesomeIcons.fingerprint, size: 24, color: p.accent),
                        )
                      : null,
                ),
                const SizedBox(height: Sp.x6),
                OnyxButton(
                  label: 'Buka',
                  expand: true,
                  loading: _busy,
                  onPressed: _pin.length >= 4 && _lockedSeconds == 0 ? _verify : null,
                ),
                TextButton(
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                  child: const Text('Keluar dari akun'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _first = '';
  String _pin = '';
  bool _confirming = false;
  String? _error;
  bool _busy = false;

  void _digit(int n) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += '$n';
      _error = null;
    });
  }

  Future<void> _next() async {
    if (_pin.length < 4) {
      setState(() => _error = 'PIN harus 4 sampai 6 digit angka.');
      return;
    }
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _pin = '';
        _first = '';
        _confirming = false;
        _error = 'Kedua PIN tidak sama. Mulai lagi.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).setPin(_pin);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: const OnyxAppBar(title: 'PIN keamanan'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_confirming ? 'Ulangi PIN' : 'Buat PIN', style: context.text.headlineSmall),
                const SizedBox(height: Sp.x2),
                SizedBox(
                  height: 40,
                  child: Text(
                    _error ?? 'PIN dipakai untuk membuka Onyx dan mengatur ulang password.',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(color: _error != null ? p.error : p.textSecondary),
                  ),
                ),
                const SizedBox(height: Sp.x4),
                PinPad(
                  length: _pin.length,
                  max: 6,
                  onDigit: _digit,
                  onBackspace: () {
                    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                  },
                ),
                const SizedBox(height: Sp.x6),
                OnyxButton(label: _confirming ? 'Simpan PIN' : 'Lanjut', expand: true, loading: _busy, onPressed: _pin.length >= 4 ? _next : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
