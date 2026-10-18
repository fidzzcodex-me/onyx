import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/models.dart';
import 'providers.dart';

class TermSession {
  TermSession(this.info, this.api) : terminal = Terminal(maxLines: 10000), controller = TerminalController() {
    _decoder = StreamController<List<int>>();
    _decoder.stream.transform(const Utf8Decoder(allowMalformed: true)).listen(terminal.write);
    terminal.onOutput = _onOutput;
    terminal.onResize = (cols, rows, pw, ph) {
      this.rows = rows;
      this.cols = cols;
      api.terminal.resize(info.id, rows, cols).catchError((Object _) {});
    };
  }

  TermInfo info;
  final Api api;
  final Terminal terminal;
  final TerminalController controller;
  late final StreamController<List<int>> _decoder;
  bool exited = false;
  int? exitCode;
  String title = '';
  String cwd = '';
  int rows = 24;
  int cols = 80;
  bool ctrl = false;
  bool alt = false;
  final ValueNotifier<int> modifiers = ValueNotifier<int>(0);

  int get id => info.id;
  bool get isSsh => info.kind == 'ssh';

  void toggleCtrl() {
    ctrl = !ctrl;
    _publish();
  }

  void toggleAlt() {
    alt = !alt;
    _publish();
  }

  void _publish() => modifiers.value = (ctrl ? 1 : 0) | (alt ? 2 : 0);

  void _onOutput(String data) {
    if (exited) return;
    var out = data;
    if ((ctrl || alt) && data.isNotEmpty) {
      if (ctrl && data.length == 1) {
        final c = data.toLowerCase().codeUnitAt(0);
        if (c >= 0x61 && c <= 0x7a) {
          out = String.fromCharCode(c - 0x60);
        } else if (c >= 0x40 && c <= 0x5f) {
          out = String.fromCharCode(c - 0x40);
        }
      }
      if (alt) out = '\x1b$out';
      ctrl = false;
      alt = false;
      _publish();
    }
    if (isSsh) {
      _localEcho(out);
    }
    send(out);
  }

  void _localEcho(String data) {
    if (data.isEmpty) return;
    final buf = StringBuffer();
    for (final unit in data.codeUnits) {
      if (unit == 0x7f || unit == 0x08) {
        buf.write('\x08 \x08');
      } else if (unit == 0x0d || unit == 0x0a) {
        buf.write('\r\n');
      } else if (unit >= 0x20 && unit != 0x7f) {
        buf.writeCharCode(unit);
      }
    }
    final text = buf.toString();
    if (text.isNotEmpty) terminal.write(text);
  }

  void send(String text) {
    if (text.isEmpty) return;
    api.terminal.write(id, Uint8List.fromList(utf8.encode(text))).catchError((Object e) {
      if (kDebugMode) {
        print('terminal write failed id=$id: $e');
      }
    });
  }

  void feed(List<int> bytes) => _decoder.add(bytes);

  void note(String text) => terminal.write(text);

  void dispose() {
    _decoder.close();
    modifiers.dispose();
  }
}

@immutable
class TermState {
  const TermState({this.sessions = const [], this.activeId, this.loading = true, this.error, this.revision = 0});

  final List<TermSession> sessions;
  final int? activeId;
  final bool loading;
  final String? error;
  final int revision;

  TermSession? get active {
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  TermState copyWith({List<TermSession>? sessions, int? activeId, bool clearActive = false, bool? loading, String? error, bool clearError = false}) {
    return TermState(
      sessions: sessions ?? this.sessions,
      activeId: clearActive ? null : (activeId ?? this.activeId),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      revision: revision + 1,
    );
  }
}

class TerminalNotifier extends StateNotifier<TermState> {
  TerminalNotifier(this._ref) : super(const TermState());

  final Ref _ref;
  StreamSubscription<TerminalEvent>? _sub;
  bool _started = false;
  Map<String, dynamic> prepared = const {};
  final StreamController<String> _bells = StreamController<String>.broadcast();

  Stream<String> get bells => _bells.stream;

  Api get _api => _ref.read(apiProvider);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = _api.terminal.events.listen(_onEvent);
    try {
      prepared = await _api.terminal.prepare();
      final existing = await _api.terminal.list();
      final sessions = <TermSession>[];
      for (final info in existing) {
        final session = TermSession(info, _api);
        final backlog = await _api.terminal.attach(info.id);
        if (backlog != null) session.feed(backlog);
        session.exited = !info.alive;
        sessions.add(session);
      }
      state = state.copyWith(
        sessions: sessions,
        activeId: sessions.isEmpty ? null : sessions.first.id,
        clearActive: sessions.isEmpty,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: describeError(error));
    }
  }

  void _onEvent(TerminalEvent event) {
    TermSession? session;
    for (final s in state.sessions) {
      if (s.id == event.id) session = s;
    }
    if (session == null) return;
    switch (event.type) {
      case 'data':
        session.feed(event.data);
      case 'exit':
        session.exited = true;
        session.exitCode = event.code;
        session.note('\r\n\x1b[90m[Proses selesai dengan kode ${event.code}]\x1b[0m\r\n');
        state = state.copyWith();
      case 'title':
        session.title = event.title;
        state = state.copyWith();
      case 'cwd':
        session.cwd = event.cwd;
        state = state.copyWith();
      case 'bell':
        HapticFeedback.mediumImpact();
        _bells.add('bell');
    }
  }

  Future<TermSession?> newLocal({String? cwd, String? title}) async {
    try {
      final settings = _ref.read(settingsProvider);
      final info = await _api.terminal.start(shell: settings.terminalShell, cwd: cwd, title: title, rows: 24, cols: 80);
      return _add(info);
    } catch (error) {
      state = state.copyWith(error: describeError(error));
      rethrow;
    }
  }

  Future<TermSession?> newSsh(String profileId) async {
    final info = await _api.terminal.startSsh(profileId, rows: 24, cols: 80);
    return _add(info);
  }

  TermSession _add(TermInfo info) {
    final session = TermSession(info, _api);
    if (info.cwd != null) session.cwd = info.cwd!;
    state = state.copyWith(sessions: [...state.sessions, session], activeId: session.id, clearError: true);
    return session;
  }

  void select(int id) {
    state = state.copyWith(activeId: id);
    _api.terminal.setVisible(id).catchError((Object _) {});
  }

  Future<void> close(int id) async {
    final target = state.sessions.where((s) => s.id == id).toList();
    if (target.isEmpty) return;
    try {
      await _api.terminal.kill(id);
    } catch (_) {}
    final remaining = state.sessions.where((s) => s.id != id).toList();
    int? next = state.activeId;
    if (next == id) next = remaining.isEmpty ? null : remaining.last.id;
    state = state.copyWith(sessions: remaining, activeId: next, clearActive: next == null);
    target.first.dispose();
  }

  Future<void> closeAll() async {
    await _api.terminal.killAll().catchError((Object _) {});
    for (final s in state.sessions) {
      s.dispose();
    }
    state = state.copyWith(sessions: [], clearActive: true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _bells.close();
    super.dispose();
  }
}

final terminalProvider = StateNotifierProvider<TerminalNotifier, TermState>((ref) => TerminalNotifier(ref));
