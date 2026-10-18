import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/highlighter.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import 'viewer_common.dart';

enum DocumentKind { json, csv }

class DocumentViewerScreen extends ConsumerStatefulWidget {
  const DocumentViewerScreen({super.key, required this.entry, required this.kind});

  final FileEntry entry;
  final DocumentKind kind;

  @override
  ConsumerState<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  int _sortColumn = -1;
  bool _sortAsc = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider).viewer;
      final data = widget.kind == DocumentKind.json ? await api.json(widget.entry.path) : await api.csv(widget.entry.path);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = OnyxError.from(error).message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Loading(label: 'Membaca dokumen');
    } else if (_error != null) {
      body = ErrorState(title: 'Dokumen tidak dapat dibaca', message: _error!, onRetry: _load);
    } else if (widget.kind == DocumentKind.json) {
      body = _json(context);
    } else {
      body = _csv(context);
    }
    return ViewerScaffold(
      path: widget.entry.path,
      actions: [ViewerActions(entry: widget.entry)],
      body: body,
    );
  }

  Widget _json(BuildContext context) {
    final p = context.palette;
    final ok = (_data['ok'] ?? false) as bool;
    final text = (_data['text'] ?? '') as String;
    final colors = SyntaxColors.of(p);
    final base = OnyxFonts.mono(size: 13, color: p.text, height: 1.5);
    return Column(
      children: [
        if (!ok)
          Container(
            width: double.infinity,
            color: p.warning.withValues(alpha: 0.14),
            padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x3),
            child: Row(
              children: [
                FaIcon(FontAwesomeIcons.triangleExclamation, size: 15, color: p.warning),
                const SizedBox(width: Sp.x3),
                Expanded(child: Text('JSON tidak valid: ${_data['error'] ?? 'galat tidak diketahui'}. Isi asli ditampilkan apa adanya.', style: context.text.bodySmall?.copyWith(color: p.text))),
              ],
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sp.x4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText.rich(TextSpan(children: Highlighter.spans(text, 'json', colors, base), style: base)),
              ),
            ),
          ),
        ),
        _FooterBar(
          label: ok ? 'JSON valid, dirapikan' : 'JSON tidak valid',
          trailing: IconButton(
            tooltip: 'Salin isi',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              toast(context, 'Isi disalin');
            },
            icon: const FaIcon(FontAwesomeIcons.copy, size: 15),
          ),
        ),
      ],
    );
  }

  Widget _csv(BuildContext context) {
    final p = context.palette;
    final rows = ((_data['rows'] ?? const []) as List).map((r) => (r as List).map((c) => c?.toString() ?? '').toList()).toList();
    if (rows.isEmpty) {
      return const EmptyState(icon: FontAwesomeIcons.table, title: 'Tabel kosong', message: 'Berkas ini tidak memiliki baris.');
    }
    final columns = ((_data['columns'] ?? 0) as num).toInt();
    final header = rows.first;
    var body = rows.skip(1).toList();
    if (_filter.isNotEmpty) {
      final needle = _filter.toLowerCase();
      body = body.where((r) => r.any((c) => c.toLowerCase().contains(needle))).toList();
    }
    if (_sortColumn >= 0) {
      body.sort((a, b) {
        final x = _sortColumn < a.length ? a[_sortColumn] : '';
        final y = _sortColumn < b.length ? b[_sortColumn] : '';
        final nx = num.tryParse(x);
        final ny = num.tryParse(y);
        final c = nx != null && ny != null ? nx.compareTo(ny) : x.toLowerCase().compareTo(y.toLowerCase());
        return _sortAsc ? c : -c;
      });
    }
    final truncated = (_data['truncated'] ?? false) as bool;
    final headStyle = context.text.labelMedium?.copyWith(color: p.text, fontWeight: FontWeight.w700);
    final cellStyle = OnyxFonts.mono(size: 12, color: p.text);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x2),
          child: TextField(
            onChanged: (v) => setState(() => _filter = v),
            decoration: InputDecoration(
              hintText: 'Saring baris',
              prefixIcon: const Padding(padding: EdgeInsets.all(14), child: FaIcon(FontAwesomeIcons.magnifyingGlass, size: 14)),
              prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: _sortColumn < 0 ? null : _sortColumn,
                  sortAscending: _sortAsc,
                  headingRowHeight: 44,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 40,
                  columnSpacing: Sp.x6,
                  horizontalMargin: Sp.x4,
                  headingRowColor: WidgetStatePropertyAll(p.surface),
                  border: TableBorder(horizontalInside: BorderSide(color: p.divider)),
                  columns: [
                    for (var i = 0; i < columns; i++)
                      DataColumn(
                        label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(i < header.length ? header[i] : '', maxLines: 1, overflow: TextOverflow.ellipsis, style: headStyle)),
                        onSort: (index, asc) => setState(() {
                          _sortColumn = index;
                          _sortAsc = asc;
                        }),
                      ),
                  ],
                  rows: [
                    for (final r in body.take(2000))
                      DataRow(
                        cells: [
                          for (var i = 0; i < columns; i++)
                            DataCell(
                              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(i < r.length ? r[i] : '', maxLines: 1, overflow: TextOverflow.ellipsis, style: cellStyle)),
                              onTap: i < r.length ? () => showInfoSheet(context, i < header.length ? header[i] : 'Sel', [MapEntry('Nilai', r[i])]) : null,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _FooterBar(label: '${body.length} baris  ·  $columns kolom${truncated ? '  ·  dipotong' : ''}'),
      ],
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: Sp.x4, right: Sp.x2),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
          child: Row(
            children: [
              Expanded(child: Text(label, style: OnyxFonts.mono(size: 12, color: p.textSecondary), overflow: TextOverflow.ellipsis)),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
