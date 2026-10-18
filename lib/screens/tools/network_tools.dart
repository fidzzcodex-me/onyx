import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';

enum _Tool { ping, dns, ports, http, ip }

List<int> parsePorts(String raw) {
  final out = <int>{};
  for (final part in raw.split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty)) {
    if (part.contains('-')) {
      final bits = part.split('-');
      final a = int.tryParse(bits.first);
      final b = int.tryParse(bits.last);
      if (a == null || b == null || a > b) throw const FormatException('Rentang port tidak valid');
      for (var i = a; i <= b && out.length <= 4096; i++) {
        out.add(i);
      }
    } else {
      final n = int.tryParse(part);
      if (n == null) throw FormatException('"$part" bukan nomor port');
      out.add(n);
    }
  }
  for (final p in out) {
    if (p < 1 || p > 65535) throw const FormatException('Port harus antara 1 dan 65535');
  }
  if (out.length > 4096) throw const FormatException('Maksimal 4096 port sekali pindai');
  return out.toList()..sort();
}

class NetworkToolsView extends ConsumerStatefulWidget {
  const NetworkToolsView({super.key});

  @override
  ConsumerState<NetworkToolsView> createState() => _NetworkToolsViewState();
}

class _NetworkToolsViewState extends ConsumerState<NetworkToolsView> {
  _Tool _tool = _Tool.ping;
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '443');
  final TextEditingController _ports = TextEditingController(text: '22,80,443,3306,8080');
  final TextEditingController _url = TextEditingController(text: 'https://');
  final TextEditingController _body = TextEditingController();
  String _method = 'GET';
  bool _running = false;
  String? _scanId;
  int _scanDone = 0;
  int _scanTotal = 0;
  Map<String, dynamic>? _result;
  String? _error;
  List<Map<String, dynamic>> _interfaces = const [];

  @override
  void initState() {
    super.initState();
    _loadInterfaces();
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _ports, _url, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInterfaces() async {
    try {
      final list = await ref.read(apiProvider).system.interfaces();
      if (mounted) setState(() => _interfaces = list);
    } catch (_) {}
  }

  Future<void> _run() async {
    final api = ref.read(apiProvider).system;
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      switch (_tool) {
        case _Tool.ping:
          _requireHost();
          final port = int.tryParse(_port.text) ?? 443;
          _result = await api.ping(_host.text.trim(), count: 5, port: port);
        case _Tool.dns:
          _requireHost();
          _result = await api.dns(_host.text.trim());
        case _Tool.ports:
          _requireHost();
          final ports = parsePorts(_ports.text);
          if (ports.isEmpty) throw const FormatException('Isi minimal satu port');
          _scanId = 'scan-${DateTime.now().microsecondsSinceEpoch}';
          _scanDone = 0;
          _scanTotal = ports.length;
          final sub = api.events.where((e) => e['type'] == 'scan' && e['id'] == _scanId).listen((e) {
            if (mounted) {
              setState(() {
                _scanDone = ((e['done'] ?? 0) as num).toInt();
                _scanTotal = ((e['total'] ?? ports.length) as num).toInt();
              });
            }
          });
          try {
            _result = await api.portScan(_scanId!, _host.text.trim(), ports);
          } finally {
            await sub.cancel();
          }
        case _Tool.http:
          final url = _url.text.trim();
          if (!RegExp(r'^https?://[^/\s]+', caseSensitive: false).hasMatch(url)) {
            throw const FormatException('URL harus diawali http:// atau https://');
          }
          _result = await api.http(_method, url, body: _body.text.isEmpty ? null : _body.text);
        case _Tool.ip:
          final ip = await api.publicIp();
          _result = {'ip': ip};
      }
    } on FormatException catch (e) {
      _error = e.message;
    } catch (error) {
      _error = OnyxError.from(error).message;
    }
    if (mounted) setState(() => _running = false);
  }

  void _requireHost() {
    if (_host.text.trim().isEmpty) throw const FormatException('Host belum diisi. Masukkan nama domain atau alamat IP.');
  }

  Future<void> _cancel() async {
    final id = _scanId;
    if (id != null) await ref.read(apiProvider).system.cancelTool(id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const labels = {_Tool.ping: 'Ping TCP', _Tool.dns: 'DNS', _Tool.ports: 'Pindai port', _Tool.http: 'HTTP', _Tool.ip: 'IP publik'};
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x8),
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final entry in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(right: Sp.x2),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _tool == entry.key,
                    onSelected: _running
                        ? null
                        : (_) => setState(() {
                              _tool = entry.key;
                              _result = null;
                              _error = null;
                            }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Sp.x3),
        OnyxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_tool == _Tool.ping || _tool == _Tool.dns || _tool == _Tool.ports) OnyxField(controller: _host, label: 'Host', hint: 'contoh.com atau 203.0.113.10', keyboard: TextInputType.url, mono: true, onSubmitted: (_) => _run()),
              if (_tool == _Tool.ping) ...[
                const SizedBox(height: Sp.x3),
                OnyxField(controller: _port, label: 'Port TCP', helper: 'Ping memakai sambungan TCP, bukan ICMP', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], mono: true),
              ],
              if (_tool == _Tool.ports) ...[
                const SizedBox(height: Sp.x3),
                OnyxField(controller: _ports, label: 'Port', helper: 'Pisahkan dengan koma. Rentang: 1-1024', mono: true),
                const SizedBox(height: Sp.x2),
                Wrap(
                  spacing: Sp.x2,
                  children: [
                    ActionChip(label: const Text('Umum'), onPressed: () => _ports.text = '21,22,23,25,53,80,110,143,443,465,587,993,995,3306,5432,6379,8080,8443'),
                    ActionChip(label: const Text('1-1024'), onPressed: () => _ports.text = '1-1024'),
                    ActionChip(label: const Text('Web'), onPressed: () => _ports.text = '80,443,3000,5000,8000,8080,8443'),
                  ],
                ),
              ],
              if (_tool == _Tool.http) ...[
                Wrap(
                  spacing: Sp.x2,
                  children: [
                    for (final m in const ['GET', 'POST', 'PUT', 'DELETE', 'HEAD'])
                      ChoiceChip(label: Text(m), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
                  ],
                ),
                const SizedBox(height: Sp.x3),
                OnyxField(controller: _url, label: 'URL', keyboard: TextInputType.url, mono: true),
                if (_method != 'GET' && _method != 'HEAD') ...[
                  const SizedBox(height: Sp.x3),
                  OnyxField(controller: _body, label: 'Isi permintaan', maxLines: 4, mono: true),
                ],
              ],
              if (_tool == _Tool.ip) Text('Meminta alamat IP publik Anda dari layanan eksternal. Perangkat harus online.', style: context.text.bodySmall),
              const SizedBox(height: Sp.x4),
              Row(
                children: [
                  Expanded(child: OnyxButton(label: _running ? 'Berjalan' : 'Jalankan', icon: FontAwesomeIcons.play, loading: _running, onPressed: _running ? null : _run)),
                  if (_running && _tool == _Tool.ports) ...[
                    const SizedBox(width: Sp.x2),
                    OnyxButton(label: 'Batal', kind: OnyxButtonKind.danger, onPressed: _cancel),
                  ],
                ],
              ),
              if (_running && _tool == _Tool.ports && _scanTotal > 0) ...[
                const SizedBox(height: Sp.x3),
                RatioBar(value: _scanDone / _scanTotal),
                const SizedBox(height: Sp.x1),
                Text('$_scanDone dari $_scanTotal port', style: OnyxFonts.mono(size: 11, color: p.textSecondary)),
              ],
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Sp.x3),
            child: OnyxCard(child: Row(children: [FaIcon(FontAwesomeIcons.circleExclamation, size: 16, color: p.error), const SizedBox(width: Sp.x3), Expanded(child: Text(_error!, style: context.text.bodyMedium))])),
          ),
        if (_result != null) Padding(padding: const EdgeInsets.only(top: Sp.x3), child: _ResultCard(tool: _tool, data: _result!)),
        if (_interfaces.isNotEmpty) ...[
          const SectionHeader('Antarmuka jaringan', padding: EdgeInsets.fromLTRB(0, Sp.x6, 0, Sp.x2)),
          for (final i in _interfaces)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.x2),
              child: OnyxCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Text('${i['name']}', style: OnyxFonts.mono(size: 13, color: p.text, weight: FontWeight.w700)), const Spacer(), StatusDot(color: (i['up'] ?? false) == true ? p.success : p.textMuted)]),
                    const SizedBox(height: Sp.x1),
                    for (final a in (i['addresses'] as List? ?? const []))
                      Text('${(a as Map)['address']}/${a['prefix']}', style: OnyxFonts.mono(size: 12, color: p.textSecondary)),
                    if (i['mac'] != null && '${i['mac']}'.isNotEmpty) Text('${i['mac']}', style: OnyxFonts.mono(size: 11, color: p.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.tool, required this.data});

  final _Tool tool;
  final Map<String, dynamic> data;

  String _ms(Object? v) => v is num && v >= 0 ? '${v.toStringAsFixed(1)} ms' : '-';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = <MapEntry<String, String>>[];
    String? copy;
    switch (tool) {
      case _Tool.ping:
        final sent = (data['sent'] ?? 0) as num;
        final lost = (data['lost'] ?? 0) as num;
        rows.addAll([
          MapEntry('Alamat', '${data['address']}'),
          MapEntry('Metode', '${data['method']}'),
          MapEntry('Terkirim', '$sent'),
          MapEntry('Hilang', '$lost (${sent == 0 ? 0 : (lost * 100 / sent).round()}%)'),
          MapEntry('Min', _ms(data['min'])),
          MapEntry('Rata-rata', _ms(data['avg'])),
          MapEntry('Maks', _ms(data['max'])),
        ]);
      case _Tool.dns:
        rows.add(MapEntry('Waktu', _ms(data['timeMs'])));
        for (final a in (data['addresses'] as List? ?? const [])) {
          final m = a as Map;
          rows.add(MapEntry(m['ipv6'] == true ? 'IPv6' : 'IPv4', '${m['address']}'));
        }
        copy = (data['addresses'] as List? ?? const []).map((e) => (e as Map)['address']).join('\n');
      case _Tool.ports:
        final open = (data['open'] as List? ?? const []).map((e) => '$e').toList();
        rows.addAll([
          MapEntry('Alamat', '${data['address']}'),
          MapEntry('Dipindai', '${data['scanned']}'),
          MapEntry('Terbuka', open.isEmpty ? 'tidak ada' : open.join(', ')),
          if (data['cancelled'] == true) const MapEntry('Status', 'Dibatalkan'),
        ]);
        copy = open.join(',');
      case _Tool.http:
        final status = ((data['status'] ?? 0) as num).toInt();
        rows.addAll([
          MapEntry('Status', '$status ${data['message'] ?? ''}'),
          MapEntry('Waktu', '${data['timeMs']} ms'),
          MapEntry('Protokol', '${data['protocol']}'),
        ]);
        copy = '${data['body'] ?? ''}';
      case _Tool.ip:
        rows.add(MapEntry('IP publik', '${data['ip']}'));
        copy = '${data['ip']}';
    }
    final headers = data['headers'] as Map?;
    final body = data['body'] as String?;
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Hasil', style: context.text.titleMedium),
              const Spacer(),
              if (copy != null)
                IconButton(
                  tooltip: 'Salin hasil',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: copy!));
                    toast(context, 'Disalin');
                  },
                  icon: const FaIcon(FontAwesomeIcons.copy, size: 15),
                ),
            ],
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 92, child: Text(r.key, style: context.text.bodySmall)),
                  Expanded(child: SelectableText(r.value, style: OnyxFonts.mono(size: 12, color: p.text))),
                ],
              ),
            ),
          if (tool == _Tool.http && headers != null && headers.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Header respons (${headers.length})', style: context.text.bodyMedium),
              children: [
                for (final e in headers.entries)
                  Align(alignment: Alignment.centerLeft, child: SelectableText('${e.key}: ${e.value}', style: OnyxFonts.mono(size: 11, color: p.textSecondary))),
              ],
            ),
          if (tool == _Tool.http && body != null && body.isNotEmpty) ...[
            const SizedBox(height: Sp.x2),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(Sp.x3),
              decoration: BoxDecoration(color: p.terminalBg, borderRadius: Rd.c, border: Border.all(color: p.border)),
              child: SingleChildScrollView(child: SelectableText(body.length > 20000 ? body.substring(0, 20000) : body, style: OnyxFonts.mono(size: 11, color: const Color(0xFFD4D4D4), height: 1.4))),
            ),
            if (data['truncated'] == true) Padding(padding: const EdgeInsets.only(top: Sp.x1), child: Text('Isi dipotong oleh batas ukuran.', style: context.text.bodySmall)),
          ],
        ],
      ),
    );
  }
}
