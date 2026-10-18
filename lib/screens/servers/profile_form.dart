import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/models.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';

const _defaultPorts = {'sftp': 22, 'scp': 22, 'ftp': 21, 'ftps': 990, 'webdav': 443};

class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({super.key, this.profile});

  final ConnProfile? profile;

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.profile?.name ?? '');
  late final TextEditingController _host = TextEditingController(text: widget.profile?.host ?? '');
  late final TextEditingController _port = TextEditingController(text: '${widget.profile?.port ?? 22}');
  late final TextEditingController _user = TextEditingController(text: widget.profile?.username ?? '');
  late final TextEditingController _secret = TextEditingController();
  late final TextEditingController _path = TextEditingController(text: widget.profile?.initialPath ?? '');
  late final TextEditingController _proxyHost = TextEditingController(text: widget.profile?.proxyHost ?? '');
  late final TextEditingController _proxyPort = TextEditingController(text: widget.profile?.proxyPort == null || widget.profile!.proxyPort == 0 ? '' : '${widget.profile!.proxyPort}');
  late final TextEditingController _keepAlive = TextEditingController(text: '${widget.profile?.keepAlive ?? 15}');
  late final TextEditingController _timeout = TextEditingController(text: '${widget.profile?.timeoutSec ?? 20}');

  late String _protocol = widget.profile?.protocol ?? 'sftp';
  late String _auth = widget.profile?.authType ?? 'password';
  late String _proxyType = widget.profile?.proxyType ?? 'none';
  String? _keyId;
  String? _jumpId;
  List<SshKey> _keys = const [];
  List<ConnProfile> _others = const [];
  bool _advanced = false;
  bool _testing = false;
  bool _saving = false;
  final Map<String, String> _errors = {};

  bool get _editing => widget.profile != null;
  bool get _ssh => _protocol == 'sftp' || _protocol == 'scp';

  @override
  void initState() {
    super.initState();
    _keyId = widget.profile?.keyId;
    _jumpId = widget.profile?.jumpId;
    _advanced = widget.profile != null && (widget.profile!.proxyType != 'none' || widget.profile!.jumpId != null);
    _loadLists();
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _secret, _path, _proxyHost, _proxyPort, _keepAlive, _timeout]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    final api = ref.read(apiProvider).sftp;
    try {
      final keys = await api.keys();
      final profiles = await api.profiles();
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _others = profiles.where((e) => e.id != widget.profile?.id && e.isSsh).toList();
        if (_keyId != null && !keys.any((k) => k.id == _keyId)) _keyId = null;
      });
    } catch (_) {}
  }

  void _setProtocol(String value) {
    final previousDefault = _defaultPorts[_protocol];
    setState(() {
      _protocol = value;
      if (int.tryParse(_port.text) == previousDefault) _port.text = '${_defaultPorts[value]}';
      if (!_ssh && value != 'sftp' && value != 'scp') _auth = 'password';
    });
  }

  bool _validate() {
    _errors.clear();
    if (_host.text.trim().isEmpty) _errors['host'] = 'Host belum diisi. Masukkan alamat server, contoh 203.0.113.10.';
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) _errors['port'] = 'Port harus angka 1 sampai 65535.';
    if (_user.text.trim().isEmpty) _errors['user'] = 'Username belum diisi.';
    if (_auth == 'key' && _ssh && _keyId == null) _errors['key'] = 'Pilih kunci SSH, atau buat dulu di halaman Kunci.';
    if (_proxyType != 'none') {
      if (_proxyHost.text.trim().isEmpty) _errors['proxyHost'] = 'Host proxy belum diisi.';
      final pp = int.tryParse(_proxyPort.text.trim());
      if (pp == null || pp < 1 || pp > 65535) _errors['proxyPort'] = 'Port proxy tidak valid.';
    }
    if (!_editing && _auth == 'password' && _secret.text.isEmpty) _errors['secret'] = 'Password belum diisi.';
    setState(() {});
    return _errors.isEmpty;
  }

  Map<String, dynamic> _payload() {
    final name = _name.text.trim().isEmpty ? '${_user.text.trim()}@${_host.text.trim()}' : _name.text.trim();
    return {
      if (widget.profile != null) 'id': widget.profile!.id,
      'name': name,
      'protocol': _protocol,
      'host': _host.text.trim(),
      'port': int.parse(_port.text.trim()),
      'username': _user.text.trim(),
      'authType': _auth,
      'keyId': _auth == 'key' ? _keyId : null,
      'proxyType': _ssh ? _proxyType : 'none',
      'proxyHost': _proxyType == 'none' ? null : _proxyHost.text.trim(),
      'proxyPort': _proxyType == 'none' ? 0 : int.tryParse(_proxyPort.text.trim()) ?? 0,
      'jumpId': _ssh ? _jumpId : null,
      'keepAlive': int.tryParse(_keepAlive.text.trim()) ?? 15,
      'timeoutSec': int.tryParse(_timeout.text.trim()) ?? 20,
      'initialPath': _path.text.trim().isEmpty ? null : _path.text.trim(),
      if (_secret.text.isNotEmpty) 'secret': _secret.text,
    };
  }

  Future<void> _test() async {
    if (!_validate()) return;
    setState(() => _testing = true);
    try {
      final result = await ref.read(apiProvider).sftp.test(_payload());
      if (!mounted) return;
      final ms = ((result['latencyMs'] ?? 0) as num).toInt();
      toast(context, 'Terhubung dalam $ms ms. Folder awal: ${result['home']}');
    } catch (error) {
      if (mounted) toastError(context, error);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(apiProvider).sftp.saveProfile(_payload());
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        toastError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: OnyxAppBar(title: _editing ? 'Ubah profil' : 'Profil baru'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Sp.x4),
              children: [
                Text('Protokol', style: context.text.labelMedium),
                const SizedBox(height: Sp.x2),
                Segmented<String>(
                  options: const {'sftp': 'SFTP', 'scp': 'SCP', 'ftp': 'FTP', 'ftps': 'FTPS', 'webdav': 'WebDAV'},
                  value: _protocol,
                  onChanged: _setProtocol,
                ),
                if (_protocol == 'ftp')
                  Padding(
                    padding: const EdgeInsets.only(top: Sp.x2),
                    child: Text('FTP polos mengirim password tanpa enkripsi. Gunakan hanya di jaringan tepercaya.', style: context.text.bodySmall?.copyWith(color: p.warning)),
                  ),
                const SizedBox(height: Sp.x4),
                OnyxField(controller: _name, label: 'Nama profil', hint: 'Server produksi', helper: 'Kosongkan untuk memakai user@host'),
                const SizedBox(height: Sp.x3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: OnyxField(controller: _host, label: 'Host', hint: '203.0.113.10', error: _errors['host'], keyboard: TextInputType.url, mono: true)),
                    const SizedBox(width: Sp.x3),
                    Expanded(
                      flex: 1,
                      child: OnyxField(controller: _port, label: 'Port', error: _errors['port'], keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], mono: true),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.x3),
                OnyxField(controller: _user, label: 'Username', error: _errors['user'], mono: true, autofillHints: const [AutofillHints.username]),
                const SizedBox(height: Sp.x4),
                if (_ssh) ...[
                  Text('Autentikasi', style: context.text.labelMedium),
                  const SizedBox(height: Sp.x2),
                  Segmented<String>(options: const {'password': 'Password', 'key': 'Kunci SSH'}, value: _auth, onChanged: (v) => setState(() => _auth = v)),
                  const SizedBox(height: Sp.x3),
                ],
                if (_auth == 'password' || !_ssh)
                  OnyxField(
                    controller: _secret,
                    label: _editing ? 'Password baru' : 'Password',
                    helper: _editing ? 'Kosongkan untuk mempertahankan password tersimpan' : 'Disimpan terenkripsi di perangkat',
                    error: _errors['secret'],
                    obscure: true,
                  ),
                if (_auth == 'key' && _ssh) ...[
                  if (_keys.isEmpty)
                    Text('Belum ada kunci. Buat atau impor dari halaman Kunci SSH.', style: context.text.bodySmall?.copyWith(color: p.warning))
                  else
                    Wrap(
                      spacing: Sp.x2,
                      runSpacing: Sp.x2,
                      children: [
                        for (final k in _keys)
                          ChoiceChip(
                            label: Text('${k.name}  ${k.type}'),
                            selected: _keyId == k.id,
                            onSelected: (_) => setState(() => _keyId = k.id),
                          ),
                      ],
                    ),
                  if (_errors['key'] != null) Padding(padding: const EdgeInsets.only(top: Sp.x1), child: Text(_errors['key']!, style: context.text.bodySmall?.copyWith(color: p.error))),
                  const SizedBox(height: Sp.x2),
                  OnyxField(controller: _secret, label: 'Passphrase kunci (opsional)', obscure: true),
                ],
                const SizedBox(height: Sp.x4),
                OnyxField(controller: _path, label: 'Folder awal (opsional)', hint: '/var/www', mono: true),
                const SizedBox(height: Sp.x3),
                InkWell(
                  onTap: () => setState(() => _advanced = !_advanced),
                  borderRadius: Rd.c,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sp.x3),
                    child: Row(
                      children: [
                        Text('Lanjutan', style: context.text.titleMedium),
                        const Spacer(),
                        AnimatedRotation(turns: _advanced ? 0.5 : 0, duration: Motion.dialog, child: const FaIcon(FontAwesomeIcons.chevronDown, size: 14)),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.screen,
                  curve: Motion.standard,
                  alignment: Alignment.topCenter,
                  child: !_advanced
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: OnyxField(controller: _keepAlive, label: 'Keep-alive (detik)', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], mono: true)),
                                const SizedBox(width: Sp.x3),
                                Expanded(child: OnyxField(controller: _timeout, label: 'Batas waktu (detik)', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], mono: true)),
                              ],
                            ),
                            if (_ssh) ...[
                              const SizedBox(height: Sp.x4),
                              Text('Proxy', style: context.text.labelMedium),
                              const SizedBox(height: Sp.x2),
                              Segmented<String>(options: const {'none': 'Tanpa', 'http': 'HTTP', 'socks5': 'SOCKS5'}, value: _proxyType, onChanged: (v) => setState(() => _proxyType = v)),
                              if (_proxyType != 'none') ...[
                                const SizedBox(height: Sp.x3),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 3, child: OnyxField(controller: _proxyHost, label: 'Host proxy', error: _errors['proxyHost'], mono: true)),
                                    const SizedBox(width: Sp.x3),
                                    Expanded(flex: 1, child: OnyxField(controller: _proxyPort, label: 'Port', error: _errors['proxyPort'], keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], mono: true)),
                                  ],
                                ),
                              ],
                              const SizedBox(height: Sp.x4),
                              Text('Jump host', style: context.text.labelMedium),
                              const SizedBox(height: Sp.x2),
                              if (_others.isEmpty)
                                Text('Simpan profil SSH lain terlebih dulu untuk dipakai sebagai jump host.', style: context.text.bodySmall)
                              else
                                Wrap(
                                  spacing: Sp.x2,
                                  runSpacing: Sp.x2,
                                  children: [
                                    ChoiceChip(label: const Text('Tanpa'), selected: _jumpId == null, onSelected: (_) => setState(() => _jumpId = null)),
                                    for (final o in _others) ChoiceChip(label: Text(o.name), selected: _jumpId == o.id, onSelected: (_) => setState(() => _jumpId = o.id)),
                                  ],
                                ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: Sp.x6),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3 + MediaQuery.paddingOf(context).bottom),
            decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
            child: Row(
              children: [
                Expanded(child: OnyxButton(label: 'Tes koneksi', icon: FontAwesomeIcons.plug, kind: OnyxButtonKind.secondary, loading: _testing, onPressed: _saving ? null : _test)),
                const SizedBox(width: Sp.x3),
                Expanded(child: OnyxButton(label: 'Simpan', icon: FontAwesomeIcons.check, loading: _saving, onPressed: _testing ? null : _save)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
