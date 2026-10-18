import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xterm/xterm.dart';

import '../../core/terminal_theme.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/nav.dart';
import '../../state/providers.dart';
import '../../state/terminal_state.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  bool _autoStarted = false;
  final Map<int, FocusNode> _focus = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(terminalProvider.notifier).start();
      if (!mounted) return;
      _maybeAutoStart();
    });
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _maybeAutoStart() async {
    if (_autoStarted) return;
    final state = ref.read(terminalProvider);
    if (state.loading || state.sessions.isNotEmpty || state.error != null) return;
    _autoStarted = true;
    await _openLocal();
  }

  Future<void> _openLocal({String? cwd}) async {
    try {
      await ref.read(terminalProvider.notifier).newLocal(cwd: cwd);
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  Future<void> _openSsh() async {
    try {
      final profiles = (await ref.read(apiProvider).sftp.profiles()).where((p) => p.isSsh).toList();
      if (!mounted) return;
      if (profiles.isEmpty) {
        toast(context, 'Belum ada profil SSH. Buat dulu di tab Server.', error: true);
        return;
      }
      await showActionSheet(
        context,
        title: 'Sambung SSH',
        subtitle: 'Pilih profil server',
        actions: [
          for (final profile in profiles)
            SheetAction(profile.name, FontAwesomeIcons.server, () async {
              try {
                await ref.read(terminalProvider.notifier).newSsh(profile.id);
              } catch (error) {
                if (mounted) toastError(context, error);
              }
            }, subtitle: '${profile.username}@${profile.host}:${profile.port}'),
        ],
      );
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  Future<void> _paste(TermSession session) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) session.terminal.paste(text);
  }

  void _copy(TermSession session) {
    final selection = session.controller.selection;
    if (selection == null) {
      toast(context, 'Pilih teks dengan menekan lama, lalu salin.');
      return;
    }
    final text = session.terminal.buffer.getText(selection);
    Clipboard.setData(ClipboardData(text: text));
    session.controller.clearSelection();
    toast(context, 'Teks disalin');
  }

  Future<void> _closeSession(TermSession session) async {
    if (!session.exited) {
      final ok = await confirm(
        context,
        title: 'Tutup sesi?',
        message: 'Proses yang sedang berjalan di "${session.title.isEmpty ? session.info.title : session.title}" akan dihentikan.',
        confirmLabel: 'Tutup sesi',
        danger: true,
      );
      if (!ok) return;
    }
    await ref.read(terminalProvider.notifier).close(session.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalProvider);
    final settings = ref.watch(settingsProvider);
    final p = context.palette;
    ref.listen<String?>(pendingTerminalCwdProvider, (previous, next) async {
      if (next == null) return;
      ref.read(pendingTerminalCwdProvider.notifier).state = null;
      await _openLocal(cwd: next);
    });
    ref.listen<AppTab>(tabProvider, (previous, next) {
      if (next == AppTab.terminal) {
        final id = ref.read(terminalProvider).activeId;
        if (id != null) ref.read(apiProvider).terminal.setVisible(id).catchError((Object _) {});
        ref.read(apiProvider).window.setKeepScreenOn(settings.keepScreenOnInTerminal).catchError((Object _) {});
        _maybeAutoStart();
      } else {
        ref.read(apiProvider).terminal.setVisible(-1).catchError((Object _) {});
        ref.read(apiProvider).window.setKeepScreenOn(false).catchError((Object _) {});
      }
    });

    final active = state.active;
    final cwd = active == null ? '' : (active.cwd.isNotEmpty ? active.cwd : (active.title.isEmpty ? active.info.title : active.title));

    return Scaffold(
      backgroundColor: p.terminalBg,
      appBar: OnyxAppBar(
        automaticLeading: false,
        title: 'Terminal',
        ribbon: active == null
            ? null
            : (cwd.startsWith('/')
                ? PathRibbon(path: cwd, prefix: active.isSsh ? 'ssh' : null)
                : SizedBox(
                    height: 28,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(cwd, maxLines: 1, overflow: TextOverflow.ellipsis, style: OnyxFonts.mono(size: 12, color: p.textSecondary)),
                    ),
                  )),
        actions: [
          IconButton(
            tooltip: 'Sesi baru',
            onPressed: () => _openLocal(),
            icon: const FaIcon(FontAwesomeIcons.plus, size: 18),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu terminal',
            icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 18),
            onSelected: (value) async {
              switch (value) {
                case 'ssh':
                  await _openSsh();
                case 'copy':
                  if (active != null) _copy(active);
                case 'paste':
                  if (active != null) await _paste(active);
                case 'clear':
                  active?.send('\x0c');
                case 'bigger':
                  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(terminalFontSize: (s.terminalFontSize + 1).clamp(9, 28)));
                case 'smaller':
                  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(terminalFontSize: (s.terminalFontSize - 1).clamp(9, 28)));
                case 'closeAll':
                  await ref.read(terminalProvider.notifier).closeAll();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'ssh', child: Text('Sesi SSH baru')),
              PopupMenuItem(value: 'copy', child: Text('Salin pilihan')),
              PopupMenuItem(value: 'paste', child: Text('Tempel')),
              PopupMenuItem(value: 'clear', child: Text('Bersihkan layar')),
              PopupMenuItem(value: 'bigger', child: Text('Perbesar huruf')),
              PopupMenuItem(value: 'smaller', child: Text('Perkecil huruf')),
              PopupMenuItem(value: 'closeAll', child: Text('Tutup semua sesi')),
            ],
          ),
        ],
        bottom: state.sessions.length > 1 ? _Tabs(state: state, onClose: _closeSession) : null,
      ),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (state.loading) return const Loading(label: 'Menyiapkan shell');
            if (state.error != null && state.sessions.isEmpty) {
              return ErrorState(
                title: 'Terminal tidak dapat dimulai',
                message: state.error!,
                onRetry: () => _openLocal(),
              );
            }
            if (state.sessions.isEmpty) {
              return EmptyState(
                icon: FontAwesomeIcons.terminal,
                title: 'Belum ada sesi',
                message: 'Mulai shell lokal atau sambung ke server lewat SSH.',
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OnyxButton(label: 'Shell lokal', icon: FontAwesomeIcons.terminal, onPressed: () => _openLocal()),
                    const SizedBox(width: Sp.x3),
                    OnyxButton(label: 'SSH', icon: FontAwesomeIcons.server, kind: OnyxButtonKind.secondary, onPressed: _openSsh),
                  ],
                ),
              );
            }
            return Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: state.sessions.indexWhere((s) => s.id == state.activeId).clamp(0, state.sessions.length - 1).toInt(),
                    children: [
                      for (final session in state.sessions)
                        _SessionView(
                          key: ValueKey<int>(session.id),
                          session: session,
                          fontSize: settings.terminalFontSize,
                          focus: _focus.putIfAbsent(session.id, FocusNode.new),
                          onRestart: () async {
                            await ref.read(terminalProvider.notifier).close(session.id);
                            await _openLocal();
                          },
                        ),
                    ],
                  ),
                ),
                if (active != null) _ExtraKeys(session: active, focus: _focus[active.id], onPaste: () => _paste(active)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tabs extends ConsumerWidget implements PreferredSizeWidget {
  const _Tabs({required this.state, required this.onClose});

  final TermState state;
  final Future<void> Function(TermSession) onClose;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Container(
      height: 44,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.x2),
        children: [
          for (final session in state.sessions)
            GestureDetector(
              onTap: () => ref.read(terminalProvider.notifier).select(session.id),
              onLongPress: () => onClose(session),
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minWidth: 88, maxWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FaIcon(session.isSsh ? FontAwesomeIcons.server : FontAwesomeIcons.terminal, size: 12, color: session.id == state.activeId ? p.accent : p.textMuted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            session.title.isEmpty ? session.info.title : session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(color: session.id == state.activeId ? p.text : p.textSecondary, decoration: session.exited ? TextDecoration.lineThrough : null),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => onClose(session),
                          child: Padding(padding: const EdgeInsets.all(4), child: FaIcon(FontAwesomeIcons.xmark, size: 11, color: p.textMuted)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    CaretMark(active: session.id == state.activeId, width: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  const _SessionView({super.key, required this.session, required this.fontSize, required this.focus, required this.onRestart});

  final TermSession session;
  final double fontSize;
  final FocusNode focus;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Stack(
      children: [
        Positioned.fill(
          child: TerminalView(
            session.terminal,
            controller: session.controller,
            focusNode: focus,
            theme: onyxTerminalTheme,
            padding: const EdgeInsets.all(Sp.x2),
            autofocus: true,
            textStyle: TerminalStyle(
              fontSize: fontSize,
              fontFamily: OnyxFonts.monoFamily,
              fontFamilyFallback: const ['monospace', 'Roboto Mono', 'Courier New'],
            ),
          ),
        ),
        if (session.exited)
          Positioned(
            left: Sp.x4,
            right: Sp.x4,
            bottom: Sp.x4,
            child: Container(
              padding: const EdgeInsets.all(Sp.x3),
              decoration: BoxDecoration(color: p.surface, borderRadius: Rd.c, border: Border.all(color: p.border)),
              child: Row(
                children: [
                  Expanded(child: Text('Sesi berakhir${session.exitCode == null ? '' : ' (kode ${session.exitCode})'}', style: context.text.bodySmall?.copyWith(color: p.text))),
                  OnyxButton(label: 'Mulai ulang', compact: true, kind: OnyxButtonKind.secondary, onPressed: onRestart),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ExtraKeys extends StatelessWidget {
  const _ExtraKeys({required this.session, required this.focus, required this.onPaste});

  final TermSession session;
  final FocusNode? focus;
  final VoidCallback onPaste;

  void _key(TerminalKey key) {
    session.terminal.keyInput(key);
    focus?.requestFocus();
  }

  void _text(String text) {
    session.terminal.textInput(text);
    focus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 48,
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: ValueListenableBuilder<int>(
        valueListenable: session.modifiers,
        builder: (context, mods, _) {
          Widget keyButton(String label, VoidCallback onTap, {bool on = false, IconData? icon, String? semantic}) {
            return Semantics(
              button: true,
              label: semantic ?? label,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  decoration: BoxDecoration(
                    color: on ? p.accentMuted : p.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: on ? p.accent : p.border),
                  ),
                  alignment: Alignment.center,
                  child: icon != null
                      ? FaIcon(icon, size: 13, color: on ? p.accent : p.textSecondary)
                      : Text(label, style: OnyxFonts.mono(size: 12, weight: FontWeight.w600, color: on ? p.accent : p.text)),
                ),
              ),
            );
          }

          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Sp.x1),
            children: [
              keyButton('Esc', () => _key(TerminalKey.escape)),
              keyButton('Tab', () => _key(TerminalKey.tab)),
              keyButton('Ctrl', session.toggleCtrl, on: mods & 1 != 0),
              keyButton('Alt', session.toggleAlt, on: mods & 2 != 0),
              keyButton('left', () => _key(TerminalKey.arrowLeft), icon: FontAwesomeIcons.arrowLeft, semantic: 'Panah kiri'),
              keyButton('up', () => _key(TerminalKey.arrowUp), icon: FontAwesomeIcons.arrowUp, semantic: 'Panah atas'),
              keyButton('down', () => _key(TerminalKey.arrowDown), icon: FontAwesomeIcons.arrowDown, semantic: 'Panah bawah'),
              keyButton('right', () => _key(TerminalKey.arrowRight), icon: FontAwesomeIcons.arrowRight, semantic: 'Panah kanan'),
              keyButton('Home', () => _key(TerminalKey.home)),
              keyButton('End', () => _key(TerminalKey.end)),
              keyButton('PgUp', () => _key(TerminalKey.pageUp)),
              keyButton('PgDn', () => _key(TerminalKey.pageDown)),
              keyButton('-', () => _text('-')),
              keyButton('/', () => _text('/')),
              keyButton('|', () => _text('|')),
              keyButton('~', () => _text('~')),
              keyButton('^C', () => session.send('\x03'), semantic: 'Ctrl C'),
              keyButton('^D', () => session.send('\x04'), semantic: 'Ctrl D'),
              keyButton('^Z', () => session.send('\x1a'), semantic: 'Ctrl Z'),
              keyButton('paste', onPaste, icon: FontAwesomeIcons.paste, semantic: 'Tempel'),
            ],
          );
        },
      ),
    );
  }
}
