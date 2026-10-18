import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'providers.dart';

@immutable
class Settings {
  const Settings({
    this.themeMode = 'dark',
    this.onboarded = false,
    this.terminalFontSize = 14,
    this.terminalShell = 'auto',
    this.bellEnabled = true,
    this.bellThresholdSec = 10,
    this.keepScreenOnInTerminal = false,
    this.showHidden = false,
    this.sort = 'name',
    this.ascending = true,
    this.useTrash = true,
    this.confirmDelete = true,
    this.editorFontSize = 14,
    this.editorWrap = false,
    this.editorLineNumbers = true,
    this.editorTabSize = 4,
    this.editorBackup = false,
    this.secureScreen = false,
    this.lockTimeoutSec = 30,
    this.transferConcurrency = 2,
    this.downloadDir = '/storage/emulated/0/Download/Onyx',
    this.lastRoot = 'home',
  });

  final String themeMode;
  final bool onboarded;
  final double terminalFontSize;
  final String terminalShell;
  final bool bellEnabled;
  final int bellThresholdSec;
  final bool keepScreenOnInTerminal;
  final bool showHidden;
  final String sort;
  final bool ascending;
  final bool useTrash;
  final bool confirmDelete;
  final double editorFontSize;
  final bool editorWrap;
  final bool editorLineNumbers;
  final int editorTabSize;
  final bool editorBackup;
  final bool secureScreen;
  final int lockTimeoutSec;
  final int transferConcurrency;
  final String downloadDir;
  final String lastRoot;

  ThemeMode get mode => switch (themeMode) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  Settings copyWith({
    String? themeMode,
    bool? onboarded,
    double? terminalFontSize,
    String? terminalShell,
    bool? bellEnabled,
    int? bellThresholdSec,
    bool? keepScreenOnInTerminal,
    bool? showHidden,
    String? sort,
    bool? ascending,
    bool? useTrash,
    bool? confirmDelete,
    double? editorFontSize,
    bool? editorWrap,
    bool? editorLineNumbers,
    int? editorTabSize,
    bool? editorBackup,
    bool? secureScreen,
    int? lockTimeoutSec,
    int? transferConcurrency,
    String? downloadDir,
    String? lastRoot,
  }) {
    return Settings(
      themeMode: themeMode ?? this.themeMode,
      onboarded: onboarded ?? this.onboarded,
      terminalFontSize: terminalFontSize ?? this.terminalFontSize,
      terminalShell: terminalShell ?? this.terminalShell,
      bellEnabled: bellEnabled ?? this.bellEnabled,
      bellThresholdSec: bellThresholdSec ?? this.bellThresholdSec,
      keepScreenOnInTerminal: keepScreenOnInTerminal ?? this.keepScreenOnInTerminal,
      showHidden: showHidden ?? this.showHidden,
      sort: sort ?? this.sort,
      ascending: ascending ?? this.ascending,
      useTrash: useTrash ?? this.useTrash,
      confirmDelete: confirmDelete ?? this.confirmDelete,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      editorWrap: editorWrap ?? this.editorWrap,
      editorLineNumbers: editorLineNumbers ?? this.editorLineNumbers,
      editorTabSize: editorTabSize ?? this.editorTabSize,
      editorBackup: editorBackup ?? this.editorBackup,
      secureScreen: secureScreen ?? this.secureScreen,
      lockTimeoutSec: lockTimeoutSec ?? this.lockTimeoutSec,
      transferConcurrency: transferConcurrency ?? this.transferConcurrency,
      downloadDir: downloadDir ?? this.downloadDir,
      lastRoot: lastRoot ?? this.lastRoot,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'onboarded': onboarded,
        'terminalFontSize': terminalFontSize,
        'terminalShell': terminalShell,
        'bellEnabled': bellEnabled,
        'bellThresholdSec': bellThresholdSec,
        'keepScreenOnInTerminal': keepScreenOnInTerminal,
        'showHidden': showHidden,
        'sort': sort,
        'ascending': ascending,
        'useTrash': useTrash,
        'confirmDelete': confirmDelete,
        'editorFontSize': editorFontSize,
        'editorWrap': editorWrap,
        'editorLineNumbers': editorLineNumbers,
        'editorTabSize': editorTabSize,
        'editorBackup': editorBackup,
        'secureScreen': secureScreen,
        'lockTimeoutSec': lockTimeoutSec,
        'transferConcurrency': transferConcurrency,
        'downloadDir': downloadDir,
        'lastRoot': lastRoot,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    const d = Settings();
    T pick<T>(String key, T fallback) {
      final value = j[key];
      if (value is T) return value;
      if (T == double && value is num) return value.toDouble() as T;
      if (T == int && value is num) return value.toInt() as T;
      return fallback;
    }

    return Settings(
      themeMode: pick('themeMode', d.themeMode),
      onboarded: pick('onboarded', d.onboarded),
      terminalFontSize: pick('terminalFontSize', d.terminalFontSize),
      terminalShell: pick('terminalShell', d.terminalShell),
      bellEnabled: pick('bellEnabled', d.bellEnabled),
      bellThresholdSec: pick('bellThresholdSec', d.bellThresholdSec),
      keepScreenOnInTerminal: pick('keepScreenOnInTerminal', d.keepScreenOnInTerminal),
      showHidden: pick('showHidden', d.showHidden),
      sort: pick('sort', d.sort),
      ascending: pick('ascending', d.ascending),
      useTrash: pick('useTrash', d.useTrash),
      confirmDelete: pick('confirmDelete', d.confirmDelete),
      editorFontSize: pick('editorFontSize', d.editorFontSize),
      editorWrap: pick('editorWrap', d.editorWrap),
      editorLineNumbers: pick('editorLineNumbers', d.editorLineNumbers),
      editorTabSize: pick('editorTabSize', d.editorTabSize),
      editorBackup: pick('editorBackup', d.editorBackup),
      secureScreen: pick('secureScreen', d.secureScreen),
      lockTimeoutSec: pick('lockTimeoutSec', d.lockTimeoutSec),
      transferConcurrency: pick('transferConcurrency', d.transferConcurrency),
      downloadDir: pick('downloadDir', d.downloadDir),
      lastRoot: pick('lastRoot', d.lastRoot),
    );
  }
}

class SettingsNotifier extends StateNotifier<Settings> {
  SettingsNotifier(this._ref) : super(const Settings());

  final Ref _ref;
  File? _file;

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/settings.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) state = Settings.fromJson(decoded);
      }
    } catch (_) {
      state = const Settings();
    }
    await _applyNative();
  }

  Future<void> update(Settings Function(Settings current) change) async {
    state = change(state);
    await _persist();
    await _applyNative();
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;
    try {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (_) {}
  }

  Future<void> _applyNative() async {
    final api = _ref.read(apiProvider);
    try {
      await api.window.setSecure(state.secureScreen);
      await api.terminal.setBell(state.bellEnabled, state.bellThresholdSec * 1000);
      await api.sftp.setConcurrency(state.transferConcurrency);
    } catch (_) {}
  }
}
