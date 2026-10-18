import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/nav.dart';
import '../../state/providers.dart';
import '../../state/terminal_state.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import 'keys_screen.dart';
import 'profile_form.dart';
import 'remote_browser.dart';
import 'transfers_screen.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  List<ConnProfile> _profiles = const [];
  bool _loading = true;
  String? _error;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profiles = await ref.read(apiProvider).sftp.profiles();
      profiles.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      if (mounted) {
        setState(() {
          _profiles = profiles;
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

  Future<void> _edit([ConnProfile? profile]) async {
    final saved = await Navigator.of(context).push<ConnProfile>(MaterialPageRoute(builder: (_) => ProfileFormScreen(profile: profile)));
    if (saved != null) _load();
  }

  Future<void> _connect(ConnProfile profile) async {
    if (_connecting != null) return;
    setState(() => _connecting = profile.id);
    try {
      final session = await ref.read(apiProvider).sftp.connect(profile.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RemoteBrowserScreen(
            sessionId: session['sessionId'] as String,
            profile: profile,
            home: (session['home'] ?? '/') as String,
          ),
        ),
      );
      if (mounted) _load();
    } catch (error) {
      if (mounted) toastError(context, error);
    } finally {
      if (mounted) setState(() => _connecting = null);
    }
  }

  Future<void> _terminal(ConnProfile profile) async {
    try {
      await ref.read(terminalProvider.notifier).newSsh(profile.id);
      ref.read(tabProvider.notifier).state = AppTab.terminal;
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  Future<void> _forget(ConnProfile profile) async {
    final ok = await confirm(
      context,
      title: 'Lupakan sidik jari host?',
      message: 'Sidik jari ${profile.host} akan dihapus. Koneksi berikutnya mempercayai kunci host yang tampil saat itu.',
      confirmLabel: 'Lupakan',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runGuarded(context, () => ref.read(apiProvider).sftp.forgetHost(profile.host, profile.port), success: 'Sidik jari host dihapus');
  }

  Future<void> _delete(ConnProfile profile) async {
    final ok = await confirm(
      context,
      title: 'Hapus profil "${profile.name}"?',
      message: 'Profil dan password tersimpannya dihapus dari perangkat ini. Server tidak terpengaruh.',
      confirmLabel: 'Hapus',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runGuarded(context, () async {
      await ref.read(apiProvider).sftp.deleteProfile(profile.id);
      await _load();
    });
  }

  void _menu(ConnProfile profile) {
    showActionSheet(
      context,
      title: profile.name,
      subtitle: '${profile.username}@${profile.host}:${profile.port}',
      actions: [
        SheetAction('Sambungkan', FontAwesomeIcons.plug, () => _connect(profile)),
        if (profile.isSsh) SheetAction('Buka terminal SSH', FontAwesomeIcons.terminal, () => _terminal(profile)),
        SheetAction('Ubah profil', FontAwesomeIcons.pen, () => _edit(profile)),
        if (profile.isSsh) SheetAction('Lupakan sidik jari host', FontAwesomeIcons.fingerprint, () => _forget(profile)),
        SheetAction('Hapus', FontAwesomeIcons.trashCan, () => _delete(profile), danger: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final transfers = ref.watch(transfersProvider);
    return Scaffold(
      appBar: OnyxAppBar(
        title: 'Server',
        automaticLeading: false,
        actions: [
          IconButton(
            tooltip: 'Kunci SSH',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KeysScreen())),
            icon: const FaIcon(FontAwesomeIcons.key, size: 16),
          ),
          IconButton(
            tooltip: 'Transfer',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransfersScreen())),
            icon: Badge(
              isLabelVisible: transfers.activeCount > 0,
              label: Text('${transfers.activeCount}'),
              backgroundColor: p.accent,
              textColor: p.onAccent,
              child: const FaIcon(FontAwesomeIcons.arrowRightArrowLeft, size: 16),
            ),
          ),
        ],
      ),
      floatingActionButton: _profiles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              icon: const FaIcon(FontAwesomeIcons.plus, size: 15),
              label: const Text('Profil baru'),
            ),
      body: _loading
          ? const Loading()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _profiles.isEmpty
                  ? EmptyState(
                      icon: FontAwesomeIcons.server,
                      title: 'Belum ada server',
                      message: 'Simpan profil SFTP, SCP, FTP, FTPS, atau WebDAV untuk menjelajah berkas dan membuka terminal SSH.',
                      action: OnyxButton(label: 'Tambah profil', icon: FontAwesomeIcons.plus, onPressed: () => _edit()),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, 96),
                        itemCount: _profiles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: Sp.x3),
                        itemBuilder: (context, i) {
                          final profile = _profiles[i];
                          final busy = _connecting == profile.id;
                          return Staggered(
                            index: i,
                            child: OnyxCard(
                              onTap: () => _connect(profile),
                              onLongPress: () => _menu(profile),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: Rd.c),
                                    child: busy
                                        ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2))
                                        : Center(child: FaIcon(profile.isSsh ? FontAwesomeIcons.terminal : FontAwesomeIcons.server, size: 16, color: p.accent)),
                                  ),
                                  const SizedBox(width: Sp.x3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(child: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium)),
                                            const SizedBox(width: Sp.x2),
                                            Pill(profile.protocol.toUpperCase()),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text('${profile.username}@${profile.host}:${profile.port}', maxLines: 1, overflow: TextOverflow.ellipsis, style: OnyxFonts.mono(size: 12, color: p.textSecondary)),
                                        if (profile.lastUsed > 0) Text('Terakhir dipakai ${formatDate(profile.lastUsed)}', style: context.text.bodySmall),
                                      ],
                                    ),
                                  ),
                                  IconButton(tooltip: 'Menu profil', onPressed: () => _menu(profile), icon: FaIcon(FontAwesomeIcons.ellipsisVertical, size: 16, color: p.textMuted)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
