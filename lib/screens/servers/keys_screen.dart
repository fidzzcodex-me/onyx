import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';

class KeysScreen extends ConsumerStatefulWidget {
  const KeysScreen({super.key});

  @override
  ConsumerState<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends ConsumerState<KeysScreen> {
  List<SshKey> _keys = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final keys = await ref.read(apiProvider).sftp.keys();
      if (mounted) {
        setState(() {
          _keys = keys;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = OnyxError.from(error).message;
        });
      }
    }
  }

  Future<void> _generate() async {
    final name = TextEditingController(text: 'onyx-${DateTime.now().year}');
    String type = 'ed25519';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Buat kunci SSH'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnyxField(controller: name, label: 'Nama kunci'),
              const SizedBox(height: Sp.x4),
              Segmented<String>(
                options: const {'ed25519': 'Ed25519', 'ecdsa': 'ECDSA', 'rsa': 'RSA 3072'},
                value: type,
                onChanged: (v) => setLocal(() => type = v),
              ),
              const SizedBox(height: Sp.x2),
              Text(type == 'rsa' ? 'RSA 3072 lebih lambat dibuat, tetapi diterima server lama.' : 'Disarankan untuk server modern.', style: ctx.text.bodySmall),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
          actions: [
            OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx, false)),
            OnyxButton(label: 'Buat', compact: true, onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await runGuarded(context, () async {
      await ref.read(apiProvider).sftp.generateKey(type, name.text.trim());
      await _load();
    }, success: 'Kunci dibuat');
  }

  Future<void> _import() async {
    final name = TextEditingController();
    final pem = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Impor kunci privat'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OnyxField(controller: name, label: 'Nama kunci'),
              const SizedBox(height: Sp.x3),
              OnyxField(controller: pem, label: 'Kunci privat (PEM atau OpenSSH)', maxLines: 6, mono: true, hint: '-----BEGIN OPENSSH PRIVATE KEY-----'),
              const SizedBox(height: Sp.x3),
              OnyxField(controller: pass, label: 'Passphrase (jika ada)', obscure: true),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
        actions: [
          OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx, false)),
          OnyxButton(
            label: 'Impor',
            compact: true,
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (pem.text.trim().isEmpty && data?.text != null) pem.text = data!.text!;
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (pem.text.trim().isEmpty) {
      toast(context, 'Kunci privat kosong. Tempel isi berkas kunci.', error: true);
      return;
    }
    await runGuarded(context, () async {
      await ref.read(apiProvider).sftp.importKey(name.text.trim().isEmpty ? 'kunci-impor' : name.text.trim(), pem.text, pass.text.isEmpty ? null : pass.text);
      await _load();
    }, success: 'Kunci diimpor');
  }

  Future<void> _delete(SshKey key) async {
    final ok = await confirm(
      context,
      title: 'Hapus kunci "${key.name}"?',
      message: 'Profil yang memakai kunci ini tidak akan bisa masuk sampai Anda memilih kunci lain.',
      confirmLabel: 'Hapus',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runGuarded(context, () async {
      await ref.read(apiProvider).sftp.deleteKey(key.id);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: OnyxAppBar(
        title: 'Kunci SSH',
        actions: [
          IconButton(tooltip: 'Impor kunci', onPressed: _import, icon: const FaIcon(FontAwesomeIcons.fileImport, size: 16)),
          IconButton(tooltip: 'Buat kunci', onPressed: _generate, icon: const FaIcon(FontAwesomeIcons.plus, size: 16)),
        ],
      ),
      body: _loading
          ? const Loading()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _keys.isEmpty
                  ? EmptyState(
                      icon: FontAwesomeIcons.key,
                      title: 'Belum ada kunci',
                      message: 'Buat kunci baru lalu tempel kunci publiknya di ~/.ssh/authorized_keys pada server.',
                      action: OnyxButton(label: 'Buat kunci', icon: FontAwesomeIcons.plus, onPressed: _generate),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Sp.x4),
                      itemCount: _keys.length,
                      separatorBuilder: (_, __) => const SizedBox(height: Sp.x3),
                      itemBuilder: (context, i) {
                        final k = _keys[i];
                        return OnyxCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  FaIcon(FontAwesomeIcons.key, size: 16, color: p.accent),
                                  const SizedBox(width: Sp.x3),
                                  Expanded(child: Text(k.name, style: context.text.titleMedium, overflow: TextOverflow.ellipsis)),
                                  Pill(k.type.toUpperCase()),
                                ],
                              ),
                              const SizedBox(height: Sp.x2),
                              Text(k.fingerprint, style: OnyxFonts.mono(size: 11, color: p.textSecondary)),
                              Text('Dibuat ${formatDate(k.createdAt)}', style: context.text.bodySmall),
                              const SizedBox(height: Sp.x3),
                              Row(
                                children: [
                                  Expanded(
                                    child: OnyxButton(
                                      label: 'Salin kunci publik',
                                      icon: FontAwesomeIcons.copy,
                                      kind: OnyxButtonKind.secondary,
                                      compact: true,
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: k.publicKey));
                                        toast(context, 'Kunci publik disalin');
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: Sp.x2),
                                  IconButton(tooltip: 'Hapus kunci', onPressed: () => _delete(k), icon: FaIcon(FontAwesomeIcons.trashCan, size: 16, color: p.error)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
