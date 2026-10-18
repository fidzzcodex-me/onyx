import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/highlighter.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';
import 'code_controller.dart';
import 'editor_source.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.source});

  final EditorSource source;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final CodeController _controller = CodeController();
  final FocusNode _focus = FocusNode();
  final UndoHistoryController _undo = UndoHistoryController();
  final TextEditingController _findField = TextEditingController();
  final TextEditingController _replaceField = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  EditorDoc? _doc;
  String? _error;
  String? _errorCode;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String _baseline = '';
  String _encoding = 'UTF-8';
  String _lineEnding = 'lf';
  bool _bom = false;
  int _modified = 0;
  int _line = 1;
  int _column = 1;
  int _length = 0;

  bool _finding = false;
  bool _regex = false;
  bool _caseSensitive = false;
  bool _showReplace = false;
  List<TextRange> _matches = const [];
  int _matchIndex = -1;
  String? _findError;
  Timer? _debounce;
  String _seenText = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _undo.dispose();
    _findField.dispose();
    _replaceField.dispose();
    _findFocus.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _load({String? encoding}) async {
    setState(() {
      _loading = true;
      _error = null;
      _errorCode = null;
    });
    try {
      final doc = await widget.source.load(ref.read(apiProvider), encoding: encoding);
      if (!mounted) return;
      _controller.language = doc.language;
      _controller.value = TextEditingValue(text: doc.text, selection: const TextSelection.collapsed(offset: 0));
      setState(() {
        _doc = doc;
        _baseline = doc.text;
        _encoding = doc.encoding;
        _lineEnding = doc.lineEnding;
        _bom = doc.bom;
        _modified = doc.modified;
        _dirty = false;
        _loading = false;
      });
      _recomputeMatches();
    } catch (error) {
      final e = OnyxError.from(error);
      if (mounted) {
        setState(() {
          _error = e.message;
          _errorCode = e.code;
          _loading = false;
        });
      }
    }
  }

  void _onChange() {
    final text = _controller.text;
    final selection = _controller.selection;
    final dirty = text != _baseline;
    var line = 1;
    var column = 1;
    if (selection.isValid) {
      final offset = selection.baseOffset.clamp(0, text.length);
      var lastBreak = -1;
      for (var i = 0; i < offset; i++) {
        if (text.codeUnitAt(i) == 10) {
          line++;
          lastBreak = i;
        }
      }
      column = offset - lastBreak;
    }
    if (dirty != _dirty || line != _line || column != _column || text.length != _length) {
      setState(() {
        _dirty = dirty;
        _line = line;
        _column = column;
        _length = text.length;
      });
    }
    final changed = text != _seenText;
    _seenText = text;
    if (_finding && changed) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _recomputeMatches);
    }
  }

  Settings get _settings => ref.read(settingsProvider);

  String get _indentUnit => ' ' * _settings.editorTabSize;

  bool get _readonly => _doc?.readonly ?? true;

  Future<void> _save({bool force = false}) async {
    if (_saving || _readonly) return;
    setState(() => _saving = true);
    try {
      final modified = await widget.source.save(
        ref.read(apiProvider),
        text: _controller.text,
        encoding: _encoding,
        lineEnding: _lineEnding,
        bom: _bom,
        backup: _settings.editorBackup,
        expectedModified: force ? null : (_modified > 0 ? _modified : null),
      );
      if (!mounted) return;
      setState(() {
        _baseline = _controller.text;
        _dirty = false;
        if (modified > 0) _modified = modified;
      });
      toast(context, 'Tersimpan');
    } catch (error) {
      final e = OnyxError.from(error);
      if (!mounted) return;
      if (e.code == 'conflict') {
        await _resolveConflict();
      } else {
        toastError(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resolveConflict() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Berkas berubah di luar editor'),
        content: const Text('Isi berkas di penyimpanan berbeda dari yang Anda buka. Timpa dengan versi Anda, atau muat ulang dan buang perubahan.'),
        actionsPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
        actionsOverflowButtonSpacing: Sp.x2,
        actions: [
          OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx)),
          OnyxButton(label: 'Muat ulang', kind: OnyxButtonKind.secondary, compact: true, onPressed: () => Navigator.pop(ctx, 'reload')),
          OnyxButton(label: 'Timpa', kind: OnyxButtonKind.danger, compact: true, onPressed: () => Navigator.pop(ctx, 'force')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'force') await _save(force: true);
    if (choice == 'reload') await _load(encoding: _encoding);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan perubahan?'),
        content: Text('"${widget.source.name}" memiliki perubahan yang belum disimpan.'),
        actionsPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
        actionsOverflowButtonSpacing: Sp.x2,
        actions: [
          OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx)),
          OnyxButton(label: 'Buang', kind: OnyxButtonKind.danger, compact: true, onPressed: () => Navigator.pop(ctx, 'discard')),
          OnyxButton(label: 'Simpan', compact: true, onPressed: () => Navigator.pop(ctx, 'save')),
        ],
      ),
    );
    if (choice == 'discard') return true;
    if (choice == 'save') {
      await _save();
      return !_dirty;
    }
    return false;
  }

  void _openFind() {
    setState(() => _finding = true);
    final selection = _controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final picked = _controller.text.substring(selection.start, selection.end);
      if (!picked.contains('\n')) _findField.text = picked;
    }
    _recomputeMatches();
    WidgetsBinding.instance.addPostFrameCallback((_) => _findFocus.requestFocus());
  }

  void _closeFind() {
    setState(() {
      _finding = false;
      _matches = const [];
      _matchIndex = -1;
      _findError = null;
    });
    _controller.setMatches(const [], -1);
    _focus.requestFocus();
  }

  RegExp? _buildPattern() {
    final query = _findField.text;
    if (query.isEmpty) return null;
    try {
      return RegExp(_regex ? query : RegExp.escape(query), caseSensitive: _caseSensitive, multiLine: true);
    } on FormatException catch (e) {
      _findError = 'Pola tidak valid: ${e.message}';
      return null;
    }
  }

  void _recomputeMatches({bool keepIndex = false}) {
    if (!mounted || !_finding) return;
    _findError = null;
    final pattern = _buildPattern();
    final found = <TextRange>[];
    if (pattern != null) {
      for (final m in pattern.allMatches(_controller.text)) {
        if (m.end == m.start) continue;
        found.add(TextRange(start: m.start, end: m.end));
        if (found.length >= 5000) break;
      }
    }
    var index = -1;
    if (found.isNotEmpty) {
      final cursor = _controller.selection.isValid ? _controller.selection.start : 0;
      index = keepIndex && _matchIndex >= 0 ? _matchIndex.clamp(0, found.length - 1) : found.indexWhere((r) => r.start >= cursor);
      if (index < 0) index = 0;
    }
    setState(() {
      _matches = found;
      _matchIndex = index;
    });
    _controller.setMatches(found, index);
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    final next = (_matchIndex + delta) % _matches.length;
    setState(() => _matchIndex = next < 0 ? next + _matches.length : next);
    _controller.setMatches(_matches, _matchIndex);
    _reveal(_matches[_matchIndex]);
  }

  void _reveal(TextRange range) {
    _controller.selection = TextSelection(baseOffset: range.start, extentOffset: range.end);
    _scrollToOffset(range.start);
  }

  void _scrollToOffset(int offset) {
    final text = _controller.text;
    final clamped = offset.clamp(0, text.length);
    var line = 0;
    for (var i = 0; i < clamped; i++) {
      if (text.codeUnitAt(i) == 10) line++;
    }
    final lineHeight = _settings.editorFontSize * 1.5;
    if (_vertical.hasClients) {
      final target = (line * lineHeight - _vertical.position.viewportDimension / 3).clamp(0.0, _vertical.position.maxScrollExtent);
      _vertical.animateTo(target, duration: Motion.screen, curve: Motion.standard);
    }
  }

  void _replaceCurrent() {
    if (_matchIndex < 0 || _matchIndex >= _matches.length || _readonly) return;
    final pattern = _buildPattern();
    if (pattern == null) return;
    final range = _matches[_matchIndex];
    final original = _controller.text.substring(range.start, range.end);
    final replacement = _regex ? original.replaceFirstMapped(pattern, (m) => _expand(_replaceField.text, m)) : _replaceField.text;
    final text = _controller.text.replaceRange(range.start, range.end, replacement);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: range.start + replacement.length),
    );
    _recomputeMatches();
  }

  void _replaceAll() {
    if (_matches.isEmpty || _readonly) return;
    final pattern = _buildPattern();
    if (pattern == null) return;
    final count = _matches.length;
    final text = _regex
        ? _controller.text.replaceAllMapped(pattern, (m) => _expand(_replaceField.text, m))
        : _controller.text.replaceAll(pattern, _replaceField.text);
    _controller.value = TextEditingValue(text: text, selection: const TextSelection.collapsed(offset: 0));
    _recomputeMatches();
    toast(context, '$count kecocokan diganti');
  }

  String _expand(String template, Match m) {
    return template.replaceAllMapped(RegExp(r'\$(\d+)'), (g) {
      final n = int.parse(g.group(1)!);
      return n <= m.groupCount ? (m.group(n) ?? '') : g.group(0)!;
    });
  }

  Future<void> _goToLine() async {
    final lines = '\n'.allMatches(_controller.text).length + 1;
    final value = await promptText(
      context,
      title: 'Ke baris',
      hint: '1 sampai $lines',
      initial: '$_line',
      confirmLabel: 'Pergi',
      keyboard: TextInputType.number,
      validator: (v) {
        final n = int.tryParse(v);
        if (n == null || n < 1 || n > lines) return 'Masukkan angka 1 sampai $lines';
        return null;
      },
    );
    if (value == null || !mounted) return;
    final target = int.parse(value);
    final text = _controller.text;
    var offset = 0;
    for (var l = 1; l < target; l++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) break;
      offset = next + 1;
    }
    _controller.selection = TextSelection.collapsed(offset: offset);
    _focus.requestFocus();
    _scrollToOffset(offset);
  }

  void _insert(String value, {int back = 0}) {
    if (_readonly) return;
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, value);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length - back),
    );
    _focus.requestFocus();
  }

  void _shiftLines(bool outdent) {
    if (_readonly) return;
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid) return;
    final from = text.lastIndexOf('\n', selection.start == 0 ? 0 : selection.start - 1) + 1;
    final fromStart = selection.start == 0 ? 0 : (text[selection.start - 1] == '\n' ? selection.start : from);
    var to = text.indexOf('\n', selection.end);
    if (to < 0) to = text.length;
    final block = text.substring(fromStart, to);
    final unit = _indentUnit;
    final shifted = block.split('\n').map((line) {
      if (!outdent) return line.isEmpty ? line : '$unit$line';
      if (line.startsWith(unit)) return line.substring(unit.length);
      if (line.startsWith('\t')) return line.substring(1);
      return line.replaceFirst(RegExp(r'^ {1,8}'), '');
    }).join('\n');
    final next = text.replaceRange(fromStart, to, shifted);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection(baseOffset: fromStart, extentOffset: fromStart + shifted.length),
    );
  }

  Future<void> _fileSettings() async {
    final doc = _doc;
    if (doc == null) return;
    await showSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final p = ctx.palette;
          return SheetFrame(
            title: 'Format berkas',
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x4),
              children: [
                Text('Akhir baris', style: ctx.text.labelMedium),
                const SizedBox(height: Sp.x2),
                Segmented<String>(
                  options: const {'lf': 'LF', 'crlf': 'CRLF', 'cr': 'CR'},
                  value: _lineEnding,
                  onChanged: (v) {
                    setState(() {
                      _lineEnding = v;
                      _dirty = true;
                    });
                    setLocal(() {});
                  },
                ),
                const SizedBox(height: Sp.x4),
                Text('Penyandian', style: ctx.text.labelMedium),
                const SizedBox(height: Sp.x2),
                if (!widget.source.canChangeEncoding)
                  Text('Berkas jarak jauh selalu dibaca dan ditulis sebagai UTF-8.', style: ctx.text.bodySmall)
                else
                  Wrap(
                    spacing: Sp.x2,
                    runSpacing: Sp.x2,
                    children: [
                      for (final e in doc.encodings)
                        ChoiceChip(
                          label: Text(e),
                          selected: e == _encoding,
                          onSelected: (_) async {
                            Navigator.pop(ctx);
                            if (e == _encoding) return;
                            if (_dirty && !await confirm(context, title: 'Buka ulang dengan $e?', message: 'Perubahan yang belum disimpan akan hilang.', confirmLabel: 'Buka ulang', danger: true)) return;
                            await _load(encoding: e);
                          },
                        ),
                    ],
                  ),
                if (widget.source.canChangeEncoding) ...[
                  const SizedBox(height: Sp.x2),
                  SwitchRow(
                    title: 'Tulis BOM',
                    subtitle: 'Penanda urutan byte di awal berkas',
                    value: _bom,
                    onChanged: (v) {
                      setState(() {
                        _bom = v;
                        _dirty = true;
                      });
                      setLocal(() {});
                    },
                  ),
                ],
                const SizedBox(height: Sp.x2),
                Text('Bahasa terdeteksi: ${doc.language}', style: ctx.text.bodySmall?.copyWith(color: p.textSecondary)),
                Text('Ukuran: ${formatBytes(doc.size)}', style: ctx.text.bodySmall),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _viewOptions() async {
    await showSheet<void>(
      context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(settingsProvider);
          final notifier = ref.read(settingsProvider.notifier);
          return SheetFrame(
            title: 'Tampilan penyunting',
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Sp.x4),
              children: [
                SwitchRow(title: 'Bungkus baris', value: s.editorWrap, onChanged: (v) => notifier.update((c) => c.copyWith(editorWrap: v))),
                SwitchRow(
                  title: 'Nomor baris',
                  subtitle: s.editorWrap ? 'Hanya tampil saat bungkus baris mati' : null,
                  value: s.editorLineNumbers,
                  onChanged: (v) => notifier.update((c) => c.copyWith(editorLineNumbers: v)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                  child: Row(
                    children: [
                      Expanded(child: Text('Ukuran huruf ${s.editorFontSize.round()}', style: ctx.text.bodyMedium)),
                      IconButton(
                        tooltip: 'Perkecil huruf',
                        onPressed: s.editorFontSize > 10 ? () => notifier.update((c) => c.copyWith(editorFontSize: c.editorFontSize - 1)) : null,
                        icon: const FaIcon(FontAwesomeIcons.minus, size: 14),
                      ),
                      IconButton(
                        tooltip: 'Perbesar huruf',
                        onPressed: s.editorFontSize < 24 ? () => notifier.update((c) => c.copyWith(editorFontSize: c.editorFontSize + 1)) : null,
                        icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                  child: Row(
                    children: [
                      Expanded(child: Text('Lebar tab', style: ctx.text.bodyMedium)),
                      SizedBox(
                        width: 160,
                        child: Segmented<int>(
                          options: const {2: '2', 4: '4', 8: '8'},
                          value: s.editorTabSize,
                          onChanged: (v) => notifier.update((c) => c.copyWith(editorTabSize: v)),
                        ),
                      ),
                    ],
                  ),
                ),
                SwitchRow(
                  title: 'Cadangan saat simpan',
                  subtitle: 'Menyalin versi lama ke berkas dengan akhiran ~',
                  value: s.editorBackup,
                  onChanged: (v) => notifier.update((c) => c.copyWith(editorBackup: v)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = ref.watch(settingsProvider);
    _controller.colors = SyntaxColors.of(p);
    _controller.matchColor = p.accent.withValues(alpha: 0.25);
    _controller.currentColor = p.accent.withValues(alpha: 0.6);
    final source = widget.source;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave() && mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: p.terminalBg,
        appBar: OnyxAppBar(
          title: '${source.name}${_dirty ? ' *' : ''}',
          ribbon: PathRibbon(path: source.path, prefix: source.origin),
          actions: [
            ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: _undo,
              builder: (context, value, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Urungkan',
                    onPressed: value.canUndo ? _undo.undo : null,
                    icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 16),
                  ),
                  IconButton(
                    tooltip: 'Ulangi',
                    onPressed: value.canRedo ? _undo.redo : null,
                    icon: const FaIcon(FontAwesomeIcons.rotateRight, size: 16),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Simpan',
              onPressed: _dirty && !_readonly && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : FaIcon(FontAwesomeIcons.floppyDisk, size: 17, color: _dirty && !_readonly ? p.accent : null),
            ),
            PopupMenuButton<String>(
              tooltip: 'Menu penyunting',
              icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 17),
              color: p.elevated,
              onSelected: (v) {
                switch (v) {
                  case 'find':
                    _openFind();
                  case 'line':
                    _goToLine();
                  case 'format':
                    _fileSettings();
                  case 'view':
                    _viewOptions();
                  case 'copy':
                    Clipboard.setData(ClipboardData(text: _controller.text));
                    toast(context, 'Seluruh isi disalin');
                  case 'reload':
                    _confirmReload();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'find', child: Text('Cari dan ganti')),
                PopupMenuItem(value: 'line', child: Text('Ke baris')),
                PopupMenuItem(value: 'format', child: Text('Format berkas')),
                PopupMenuItem(value: 'view', child: Text('Tampilan')),
                PopupMenuItem(value: 'copy', child: Text('Salin semua')),
                PopupMenuItem(value: 'reload', child: Text('Muat ulang dari penyimpanan')),
              ],
            ),
          ],
        ),
        body: _body(context, settings),
      ),
    );
  }

  Future<void> _confirmReload() async {
    if (_dirty && !await confirm(context, title: 'Muat ulang?', message: 'Perubahan yang belum disimpan akan hilang.', confirmLabel: 'Muat ulang', danger: true)) return;
    if (mounted) await _load(encoding: widget.source.canChangeEncoding ? _encoding : null);
  }

  Widget _body(BuildContext context, Settings settings) {
    final p = context.palette;
    if (_loading) return const Loading(label: 'Membuka berkas');
    if (_error != null) {
      final binary = _errorCode == 'binary';
      return ErrorState(
        title: binary ? 'Berkas biner' : 'Tidak dapat dibuka',
        message: _error!,
        onRetry: binary ? null : _load,
      );
    }
    final doc = _doc!;
    return Column(
      children: [
        if (doc.readonly) _Banner(color: p.warning, text: 'Berkas hanya-baca. Perubahan tidak dapat disimpan.'),
        if (_controller.text.length > Highlighter.maxChars) _Banner(color: p.info, text: 'Berkas besar: penyorotan sintaks dimatikan agar tetap lancar.'),
        if (_finding) _findBar(context),
        Expanded(child: _editor(context, settings)),
        _statusBar(context),
        _ExtraKeys(
          enabled: !_readonly,
          onInsert: _insert,
          onTab: () => _insert(_indentUnit),
          onIndent: () => _shiftLines(false),
          onOutdent: () => _shiftLines(true),
        ),
      ],
    );
  }

  Widget _editor(BuildContext context, Settings settings) {
    final p = context.palette;
    final fontSize = settings.editorFontSize;
    final style = OnyxFonts.mono(size: fontSize, color: const Color(0xFFD4D4D4), height: 1.5);
    final wrap = settings.editorWrap;
    final numbers = settings.editorLineNumbers && !wrap;
    final lineCount = '\n'.allMatches(_controller.text).length + 1;
    final digits = lineCount.toString().length;
    final gutterWidth = numbers ? digits * fontSize * 0.62 + Sp.x4 + Sp.x2 : 0.0;
    final themeStyle = style.copyWith(color: p.isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1F1F1F));
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      undoController: _undo,
      readOnly: _readonly,
      maxLines: null,
      expands: false,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      style: themeStyle,
      cursorColor: p.accent,
      cursorWidth: 2,
      scrollPadding: const EdgeInsets.all(Sp.x16 * 2),
      inputFormatters: [AutoIndentFormatter(_indentUnit)],
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.fromLTRB(Sp.x2, Sp.x3, Sp.x4, Sp.x16 * 2),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        Widget content;
        if (wrap) {
          content = field;
        } else {
          final painter = TextPainter(text: TextSpan(text: 'M', style: themeStyle), textDirection: TextDirection.ltr)..layout();
          var longest = 0;
          for (final line in _controller.text.split('\n')) {
            if (line.length > longest) longest = line.length;
          }
          final needed = longest * painter.width + Sp.x6 * 2 + Sp.x4;
          final width = needed < box.maxWidth - gutterWidth ? box.maxWidth - gutterWidth : needed;
          content = Scrollbar(
            controller: _horizontal,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: width, child: field),
            ),
          );
        }
        final gutter = numbers
            ? Container(
                width: gutterWidth,
                padding: const EdgeInsets.only(top: Sp.x3, right: Sp.x2),
                alignment: Alignment.topRight,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: p.divider))),
                child: Text(
                  List.generate(lineCount, (i) => '${i + 1}').join('\n'),
                  textAlign: TextAlign.right,
                  style: OnyxFonts.mono(size: fontSize, color: p.textMuted, height: 1.5),
                ),
              )
            : null;
        return Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (gutter != null) gutter,
                  Expanded(child: content),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _findBar(BuildContext context) {
    final p = context.palette;
    final label = _findField.text.isEmpty ? '' : (_matches.isEmpty ? '0' : '${_matchIndex + 1}/${_matches.length}${_matches.length >= 5000 ? '+' : ''}');
    return Container(
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x1, Sp.x2),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findField,
                  focusNode: _findFocus,
                  style: OnyxFonts.mono(size: 14, color: p.text),
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => _recomputeMatches(),
                  onSubmitted: (_) => _step(1),
                  decoration: InputDecoration(
                    hintText: 'Cari',
                    isDense: true,
                    errorText: _findError,
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: Sp.x3),
                      child: Center(widthFactor: 1, child: Text(label, style: OnyxFonts.mono(size: 12, color: p.textSecondary))),
                    ),
                  ),
                ),
              ),
              IconButton(tooltip: 'Sebelumnya', onPressed: _matches.isEmpty ? null : () => _step(-1), icon: const FaIcon(FontAwesomeIcons.chevronUp, size: 14)),
              IconButton(tooltip: 'Berikutnya', onPressed: _matches.isEmpty ? null : () => _step(1), icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 14)),
              IconButton(tooltip: 'Tutup pencarian', onPressed: _closeFind, icon: const FaIcon(FontAwesomeIcons.xmark, size: 15)),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ToggleChip(label: 'Aa', tooltip: 'Peka huruf besar', value: _caseSensitive, onTap: () {
                  setState(() => _caseSensitive = !_caseSensitive);
                  _recomputeMatches();
                }),
                const SizedBox(width: Sp.x2),
                _ToggleChip(label: '.*', tooltip: 'Ekspresi reguler', value: _regex, onTap: () {
                  setState(() => _regex = !_regex);
                  _recomputeMatches();
                }),
                const SizedBox(width: Sp.x2),
                _ToggleChip(label: 'Ganti', tooltip: 'Tampilkan penggantian', value: _showReplace, onTap: () => setState(() => _showReplace = !_showReplace)),
              ],
            ),
          ),
          if (_showReplace)
            Padding(
              padding: const EdgeInsets.only(top: Sp.x2),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replaceField,
                      style: OnyxFonts.mono(size: 14, color: p.text),
                      decoration: InputDecoration(hintText: _regex ? 'Ganti dengan (\$1 untuk grup)' : 'Ganti dengan', isDense: true),
                    ),
                  ),
                  const SizedBox(width: Sp.x2),
                  OnyxButton(label: 'Ganti', kind: OnyxButtonKind.secondary, compact: true, onPressed: _matches.isEmpty || _readonly ? null : _replaceCurrent),
                  const SizedBox(width: Sp.x1),
                  OnyxButton(label: 'Semua', kind: OnyxButtonKind.secondary, compact: true, onPressed: _matches.isEmpty || _readonly ? null : _replaceAll),
                  const SizedBox(width: Sp.x2),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBar(BuildContext context) {
    final p = context.palette;
    final language = _doc?.language ?? 'plaintext';
    final parts = <String>[
      'Brs $_line, Kol $_column',
      _encoding,
      _lineEnding.toUpperCase(),
      language == 'plaintext' ? 'Teks' : language,
      formatBytes(_length),
    ];
    return Container(
      height: 28,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.divider))),
      child: GestureDetector(
        onTap: _fileSettings,
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(parts.join('   '), style: OnyxFonts.mono(size: 11, color: p.textSecondary)),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
      child: Text(text, style: context.text.bodySmall?.copyWith(color: context.palette.text)),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.tooltip, required this.value, required this.onTap});

  final String label;
  final String tooltip;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
          child: AnimatedContainer(
            duration: Motion.dialog,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
            decoration: BoxDecoration(
              color: value ? p.accentMuted.withValues(alpha: 0.5) : p.surfaceAlt,
              borderRadius: Rd.c,
              border: Border.all(color: value ? p.accent : p.border),
            ),
            child: Text(label, style: OnyxFonts.mono(size: 13, color: value ? p.text : p.textSecondary, weight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _ExtraKeys extends StatelessWidget {
  const _ExtraKeys({required this.enabled, required this.onInsert, required this.onTab, required this.onIndent, required this.onOutdent});

  final bool enabled;
  final void Function(String value, {int back}) onInsert;
  final VoidCallback onTab;
  final VoidCallback onIndent;
  final VoidCallback onOutdent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pairs = <(String, String, int)>[
      ('{ }', '{}', 1),
      ('( )', '()', 1),
      ('[ ]', '[]', 1),
      ('" "', '""', 1),
      ("' '", "''", 1),
      ('<>', '<>', 1),
    ];
    final singles = ['=', ';', ':', '/', '\\', '|', '&', '!', '#', '\$', '*', '-', '_', '+', '%'];
    Widget key(String label, VoidCallback? onTap, {String? tooltip}) => Tooltip(
          message: tooltip ?? label,
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: Sp.x2),
              child: Text(label, style: OnyxFonts.mono(size: 15, color: enabled ? p.text : p.textDisabled, weight: FontWeight.w500)),
            ),
          ),
        );
    return Container(
      height: 44,
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.divider))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          key('Tab', onTab, tooltip: 'Sisipkan indentasi'),
          key('>>', onIndent, tooltip: 'Geser baris ke kanan'),
          key('<<', onOutdent, tooltip: 'Geser baris ke kiri'),
          for (final (label, value, back) in pairs) key(label, () => onInsert(value, back: back)),
          for (final s in singles) key(s, () => onInsert(s)),
        ],
      ),
    );
  }
}
