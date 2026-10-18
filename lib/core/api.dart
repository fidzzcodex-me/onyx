import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'errors.dart';
import 'models.dart';

class _Bridge {
  _Bridge(String name) : channel = MethodChannel(name);

  final MethodChannel channel;

  Future<T?> call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } catch (error) {
      throw OnyxError.from(error);
    }
  }

  Future<Map<String, dynamic>> map(String method, [Map<String, dynamic>? args]) async {
    final value = await call<Object>(method, args);
    return asMap(value);
  }

  Future<List<Map<String, dynamic>>> list(String method, [Map<String, dynamic>? args]) async {
    final value = await call<Object>(method, args);
    return asMapList(value);
  }

  Future<void> run(String method, [Map<String, dynamic>? args]) async {
    await call<Object>(method, args);
  }
}

Stream<Map<String, dynamic>> _events(String name) {
  return EventChannel(name).receiveBroadcastStream().map(asMap);
}

class AuthApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/auth');

  Future<AppUser> register(String name, String email, String password) async =>
      AppUser.fromMap(await _b.map('register', {'name': name, 'email': email, 'password': password}));

  Future<AppUser> login(String email, String password, bool remember) async =>
      AppUser.fromMap(await _b.map('login', {'email': email, 'password': password, 'remember': remember}));

  Future<AppUser> loginGuest() async => AppUser.fromMap(await _b.map('loginGuest'));

  Future<void> logout() => _b.run('logout');

  Future<AppUser?> currentUser() async {
    final value = await _b.call<Object>('currentUser');
    if (value == null) return null;
    return AppUser.fromMap(asMap(value));
  }

  Future<bool> hasAccounts() async => (await _b.call<bool>('hasAccounts')) ?? false;

  Future<AppUser> updateProfile(String name, String email) async =>
      AppUser.fromMap(await _b.map('updateProfile', {'name': name, 'email': email}));

  Future<void> changePassword(String oldPassword, String newPassword) =>
      _b.run('changePassword', {'oldPassword': oldPassword, 'newPassword': newPassword});

  Future<void> resetPassword(String email, String newPassword) =>
      _b.run('resetPassword', {'email': email, 'newPassword': newPassword});

  Future<void> deleteAccount() => _b.run('deleteAccount');

  Future<bool> hasPin() async => (await _b.call<bool>('hasPin')) ?? false;

  Future<void> setPin(String pin) => _b.run('setPin', {'pin': pin});

  Future<void> clearPin() => _b.run('clearPin');

  Future<PinResult> verifyPin(String pin) async {
    final m = await _b.map('verifyPin', {'pin': pin});
    return PinResult(
      ok: (m['ok'] ?? false) as bool,
      lockedMs: ((m['lockedMs'] ?? 0) as num).toInt(),
      attemptsLeft: ((m['attemptsLeft'] ?? 0) as num).toInt(),
    );
  }

  Future<String> biometricAvailability() async => (await _b.call<String>('biometricAvailability')) ?? 'unavailable';

  Future<bool> isBiometricEnabled() async => (await _b.call<bool>('isBiometricEnabled')) ?? false;

  Future<void> setBiometricEnabled(bool enabled) => _b.run('setBiometricEnabled', {'enabled': enabled});

  Future<bool> biometricAuthenticate({String? title, String? subtitle}) async {
    final m = await _b.map('biometricAuthenticate', {'title': title, 'subtitle': subtitle});
    return (m['ok'] ?? false) as bool;
  }
}

class PinResult {
  const PinResult({required this.ok, required this.lockedMs, required this.attemptsLeft});

  final bool ok;
  final int lockedMs;
  final int attemptsLeft;
}

class TerminalEvent {
  const TerminalEvent(this.type, this.id, this.raw);

  final String type;
  final int id;
  final Map<String, dynamic> raw;

  Uint8List get data => raw['data'] as Uint8List;
  int get code => ((raw['code'] ?? 0) as num).toInt();
  String get title => (raw['title'] ?? '') as String;
  String get cwd => (raw['cwd'] ?? '') as String;
  int get elapsedMs => ((raw['elapsedMs'] ?? 0) as num).toInt();
}

class TerminalApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/terminal');

  Stream<TerminalEvent> get events => _events('com.onyx.terminal/terminal_stream').map(
        (m) => TerminalEvent((m['type'] ?? '') as String, ((m['id'] ?? -1) as num).toInt(), m),
      );

  Future<Map<String, dynamic>> prepare() => _b.map('prepare');

  Future<TermInfo> start({
    String shell = 'auto',
    String? cwd,
    Map<String, String>? env,
    String? pathExtra,
    String? title,
    required int rows,
    required int cols,
  }) async {
    final m = await _b.map('start', {
      'shell': shell,
      'cwd': cwd,
      'env': env,
      'pathExtra': pathExtra,
      'title': title,
      'rows': rows,
      'cols': cols,
    });
    return TermInfo.fromMap(m);
  }

  Future<TermInfo> startSsh(String profileId, {required int rows, required int cols}) async =>
      TermInfo.fromMap(await _b.map('startSsh', {'profileId': profileId, 'rows': rows, 'cols': cols}));

  Future<void> write(int id, Uint8List data) => _b.run('write', {'id': id, 'data': data});

  Future<void> resize(int id, int rows, int cols) => _b.run('resize', {'id': id, 'rows': rows, 'cols': cols});

  Future<void> kill(int id) => _b.run('kill', {'id': id});

  Future<void> killAll() => _b.run('killAll');

  Future<List<TermInfo>> list() async => (await _b.list('list')).map(TermInfo.fromMap).toList();

  Future<Uint8List?> attach(int id) async {
    final m = await _b.map('attach', {'id': id});
    final backlog = m['backlog'];
    return backlog is Uint8List ? backlog : null;
  }

  Future<void> setBell(bool enabled, int thresholdMs) =>
      _b.run('setBell', {'enabled': enabled, 'thresholdMs': thresholdMs});

  Future<void> setVisible(int id) => _b.run('setVisible', {'id': id});
}

class SftpApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/sftp');

  Stream<Map<String, dynamic>> get events => _events('com.onyx.terminal/sftp_stream');

  Future<List<ConnProfile>> profiles() async => (await _b.list('profiles')).map(ConnProfile.fromMap).toList();

  Future<ConnProfile> saveProfile(Map<String, dynamic> profile) async =>
      ConnProfile.fromMap(await _b.map('saveProfile', {'profile': profile}));

  Future<void> deleteProfile(String id) => _b.run('deleteProfile', {'id': id});

  Future<Map<String, dynamic>> test(Map<String, dynamic> profile) => _b.map('test', {'profile': profile});

  Future<Map<String, dynamic>> connect(String profileId) => _b.map('connect', {'profileId': profileId});

  Future<void> disconnect(String sessionId) => _b.run('disconnect', {'sessionId': sessionId});

  Future<RemoteListing> list(String sessionId, String? path) async {
    final m = await _b.map('list', {'sessionId': sessionId, 'path': path});
    return RemoteListing(m['path'] as String, asMapList(m['entries']).map(FileEntry.fromMap).toList());
  }

  Future<void> mkdir(String sessionId, String path) => _b.run('mkdir', {'sessionId': sessionId, 'path': path});

  Future<void> delete(String sessionId, String path, {bool recursive = true}) =>
      _b.run('delete', {'sessionId': sessionId, 'path': path, 'recursive': recursive});

  Future<void> rename(String sessionId, String from, String to) =>
      _b.run('rename', {'sessionId': sessionId, 'from': from, 'to': to});

  Future<void> chmod(String sessionId, String path, int mode) =>
      _b.run('chmod', {'sessionId': sessionId, 'path': path, 'mode': mode});

  Future<String> readText(String sessionId, String path) async =>
      (await _b.call<String>('readText', {'sessionId': sessionId, 'path': path})) ?? '';

  Future<void> writeText(String sessionId, String path, String text) =>
      _b.run('writeText', {'sessionId': sessionId, 'path': path, 'text': text});

  Future<int> upload(String sessionId, String local, String remote) async =>
      (await _b.call<int>('upload', {'sessionId': sessionId, 'local': local, 'remote': remote})) ?? 0;

  Future<int> download(String sessionId, String remote, String localDir) async =>
      (await _b.call<int>('download', {'sessionId': sessionId, 'remote': remote, 'localDir': localDir})) ?? 0;

  Future<List<TransferItem>> queue() async => (await _b.list('queue')).map(TransferItem.fromMap).toList();

  Future<void> pause(String id) => _b.run('pause', {'id': id});

  Future<void> resume(String id) => _b.run('resume', {'id': id});

  Future<void> retry(String id) => _b.run('retry', {'id': id});

  Future<void> cancel(String id) => _b.run('cancel', {'id': id});

  Future<void> cancelAll() => _b.run('cancelAll');

  Future<void> clearFinished() => _b.run('clearFinished');

  Future<void> setConcurrency(int value) => _b.run('setConcurrency', {'value': value});

  Future<List<Map<String, dynamic>>> compare(String sessionId, String local, String remote) =>
      _b.list('compare', {'sessionId': sessionId, 'local': local, 'remote': remote});

  Future<int> sync(String sessionId, String local, String remote, String mode) async =>
      (await _b.call<int>('sync', {'sessionId': sessionId, 'local': local, 'remote': remote, 'mode': mode})) ?? 0;

  Future<List<SshKey>> keys() async => (await _b.list('keys')).map(SshKey.fromMap).toList();

  Future<SshKey> generateKey(String type, String name) async =>
      SshKey.fromMap(await _b.map('generateKey', {'type': type, 'name': name}));

  Future<SshKey> importKey(String name, String pem, String? passphrase) async =>
      SshKey.fromMap(await _b.map('importKey', {'name': name, 'pem': pem, 'passphrase': passphrase}));

  Future<void> deleteKey(String id) => _b.run('deleteKey', {'id': id});

  Future<void> forgetHost(String host, int port) => _b.run('forgetHost', {'host': host, 'port': port});
}

class RemoteListing {
  const RemoteListing(this.path, this.entries);

  final String path;
  final List<FileEntry> entries;
}

class FsListing {
  const FsListing({required this.path, required this.parent, required this.hiddenCount, required this.entries});

  final String path;
  final String? parent;
  final int hiddenCount;
  final List<FileEntry> entries;
}

class OpEvent {
  const OpEvent(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get kind => (raw['kind'] ?? '') as String;
  String get state => (raw['state'] ?? '') as String;
  int get done => ((raw['done'] ?? 0) as num).toInt();
  int get total => ((raw['total'] ?? 0) as num).toInt();
  String get current => (raw['current'] ?? '') as String;
  String? get error => raw['error'] as String?;
  bool get finished => state == 'done' || state == 'error' || state == 'canceled';
  double get ratio => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

class FsApi {
  FsApi() {
    _sub = events.listen(_route);
  }

  final _Bridge _b = _Bridge('com.onyx.terminal/fs');
  late final StreamSubscription<Map<String, dynamic>> _sub;
  final Stream<Map<String, dynamic>> events = _events('com.onyx.terminal/fs_events').asBroadcastStream();
  final Map<String, StreamController<OpEvent>> _ops = {};
  final Map<String, OpEvent> _early = {};

  void _route(Map<String, dynamic> m) {
    if (m['type'] != 'op') return;
    final event = OpEvent(m);
    final controller = _ops[event.id];
    if (controller != null) {
      controller.add(event);
      if (event.finished) {
        controller.close();
        _ops.remove(event.id);
      }
    } else if (event.finished) {
      _early[event.id] = event;
      if (_early.length > 32) _early.remove(_early.keys.first);
    }
  }

  Stream<OpEvent> watchOp(String id) {
    final early = _early.remove(id);
    if (early != null) return Stream<OpEvent>.value(early);
    final controller = _ops.putIfAbsent(id, () => StreamController<OpEvent>.broadcast());
    return controller.stream;
  }

  Future<OpEvent> awaitOp(String id, {void Function(OpEvent event)? onProgress}) async {
    OpEvent? last;
    await for (final event in watchOp(id)) {
      last = event;
      if (event.finished) break;
      onProgress?.call(event);
    }
    if (last == null) throw OnyxError('no_result', 'Operasi berakhir tanpa hasil');
    if (last.state == 'error') throw OnyxError((last.raw['code'] ?? 'op_failed') as String, last.error ?? 'Operasi gagal');
    return last;
  }

  Stream<String> changes() => events.where((e) => e['type'] == 'change').map((e) => e['path'] as String);

  Future<List<StorageRoot>> roots() async => (await _b.list('roots')).map(StorageRoot.fromMap).toList();

  Future<bool> hasAccess() async => (await _b.call<bool>('hasAccess')) ?? false;

  Future<void> openAccessSettings() => _b.run('openAccessSettings');

  Future<FsListing> list(String path, {bool showHidden = false, String sort = 'name', bool ascending = true}) async {
    final m = await _b.map('list', {'path': path, 'showHidden': showHidden, 'sort': sort, 'ascending': ascending});
    return FsListing(
      path: m['path'] as String,
      parent: m['parent'] as String?,
      hiddenCount: ((m['hiddenCount'] ?? 0) as num).toInt(),
      entries: asMapList(m['entries']).map(FileEntry.fromMap).toList(),
    );
  }

  Future<FileEntry?> stat(String path) async {
    final value = await _b.call<Object>('stat', {'path': path});
    return value == null ? null : FileEntry.fromMap(asMap(value));
  }

  Future<bool> exists(String path) async => (await _b.call<bool>('exists', {'path': path})) ?? false;

  Future<void> mkdir(String path) => _b.run('mkdir', {'path': path});

  Future<void> createFile(String path) => _b.run('createFile', {'path': path});

  Future<void> rename(String from, String to) => _b.run('rename', {'from': from, 'to': to});

  Future<int> delete(List<String> paths, {bool trash = true}) async =>
      (await _b.call<int>('delete', {'paths': paths, 'trash': trash})) ?? 0;

  Future<OpEvent> copy(
    List<String> sources,
    String dest, {
    bool move = false,
    String conflict = 'rename',
    void Function(OpEvent event)? onProgress,
  }) async {
    final id = await _b.call<String>('copy', {'sources': sources, 'dest': dest, 'move': move, 'conflict': conflict});
    return awaitOp(id!, onProgress: onProgress);
  }

  Future<void> cancelOp(String id) => _b.run('cancelOp', {'id': id});

  Future<Map<String, dynamic>> properties(String path) => _b.map('properties', {'path': path});

  Future<void> chmod(String path, int mode, {bool recursive = false}) =>
      _b.run('chmod', {'path': path, 'mode': mode, 'recursive': recursive});

  Future<void> symlink(String target, String link) => _b.run('symlink', {'target': target, 'link': link});

  Future<String> checksum(String path, String algorithm) async =>
      (await _b.call<String>('checksum', {'path': path, 'algorithm': algorithm})) ?? '';

  Future<(String, Future<OpEvent>)> startSearch(
    String root,
    String query, {
    bool regex = false,
    bool caseSensitive = false,
    bool hidden = false,
  }) async {
    final id = await _b.call<String>('search', {
      'root': root,
      'query': query,
      'regex': regex,
      'caseSensitive': caseSensitive,
      'hidden': hidden,
    });
    return (id!, awaitOp(id));
  }

  Future<(String, Future<OpEvent>)> startDuplicates(String root, {int minSize = 1024}) async {
    final id = await _b.call<String>('duplicates', {'root': root, 'minSize': minSize});
    return (id!, awaitOp(id));
  }

  Future<List<Map<String, dynamic>>> trashList() => _b.list('trashList');

  Future<String> trashRestore(String id) async => (await _b.call<String>('trashRestore', {'id': id})) ?? '';

  Future<void> trashEmpty({String? id}) => _b.run('trashEmpty', {'id': id});

  Future<List<Map<String, dynamic>>> bookmarks({String? type}) => _b.list('bookmarks', {'type': type});

  Future<String> addBookmark(String type, String value, {String? title, String? extra}) async =>
      (await _b.call<String>('addBookmark', {'type': type, 'value': value, 'title': title, 'extra': extra})) ?? '';

  Future<void> removeBookmark(String id) => _b.run('removeBookmark', {'id': id});

  Future<void> watch(String? path) => _b.run('watch', {'path': path});

  Future<void> open(String path, {String? mime, bool chooser = false}) =>
      _b.run('open', {'path': path, 'mime': mime, 'chooser': chooser});

  Future<void> share(String path, {String? mime}) => _b.run('share', {'path': path, 'mime': mime});

  Future<bool> archiveSupported(String path) async => (await _b.call<bool>('archiveSupported', {'path': path})) ?? false;

  Future<List<Map<String, dynamic>>> archiveList(String path) async {
    final m = await _b.map('archiveList', {'path': path});
    return asMapList(m['entries']);
  }

  Future<Uint8List> archiveRead(String path, String entry) async =>
      (await _b.call<Uint8List>('archiveRead', {'path': path, 'entry': entry})) ?? Uint8List(0);

  Future<OpEvent> extract(String path, String dest, {List<String>? only, void Function(OpEvent event)? onProgress}) async {
    final id = await _b.call<String>('extract', {'path': path, 'dest': dest, 'only': only ?? <String>[]});
    return awaitOp(id!, onProgress: onProgress);
  }

  Future<OpEvent> compress(
    List<String> sources,
    String output,
    String format, {
    void Function(OpEvent event)? onProgress,
  }) async {
    final id = await _b.call<String>('compress', {'sources': sources, 'output': output, 'format': format});
    return awaitOp(id!, onProgress: onProgress);
  }

  void dispose() {
    _sub.cancel();
  }
}

class EditorApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/editor');

  Future<Map<String, dynamic>> read(String path, {String? encoding}) =>
      _b.map('read', {'path': path, 'encoding': encoding});

  Future<Map<String, dynamic>> write({
    required String path,
    required String text,
    required String encoding,
    required String lineEnding,
    required bool bom,
    required bool backup,
    int? expectedModified,
  }) =>
      _b.map('write', {
        'path': path,
        'text': text,
        'encoding': encoding,
        'lineEnding': lineEnding,
        'bom': bom,
        'backup': backup,
        'expectedModified': expectedModified ?? 0,
      });

  Future<String> language(String path) async => (await _b.call<String>('language', {'path': path})) ?? 'plaintext';
}

class ViewerApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/viewer');

  Future<Map<String, dynamic>> imageInfo(String path) => _b.map('imageInfo', {'path': path});

  Future<Uint8List> imageThumb(String path, {int size = 256}) async =>
      (await _b.call<Uint8List>('imageThumb', {'path': path, 'size': size})) ?? Uint8List(0);

  Future<Map<String, dynamic>> videoInfo(String path) => _b.map('videoInfo', {'path': path});

  Future<Uint8List> videoThumb(String path, {int positionMs = 0, int size = 320}) async =>
      (await _b.call<Uint8List>('videoThumb', {'path': path, 'positionMs': positionMs, 'size': size})) ?? Uint8List(0);

  Future<Map<String, dynamic>> audioInfo(String path) => _b.map('audioInfo', {'path': path});

  Future<Map<String, dynamic>> pdfInfo(String path) => _b.map('pdfInfo', {'path': path});

  Future<Map<String, dynamic>> pdfPage(String path, int index, int width) =>
      _b.map('pdfPage', {'path': path, 'index': index, 'width': width});

  Future<Map<String, dynamic>> hexRead(String path, int offset, int length) =>
      _b.map('hexRead', {'path': path, 'offset': offset, 'length': length});

  Future<int> hexFind(String path, String hex, int from) async =>
      (await _b.call<int>('hexFind', {'path': path, 'hex': hex, 'from': from})) ?? -1;

  Future<int> textFind(String path, String text, int from) async =>
      (await _b.call<int>('textFind', {'path': path, 'text': text, 'from': from})) ?? -1;

  Future<Map<String, dynamic>> json(String path) => _b.map('json', {'path': path});

  Future<Map<String, dynamic>> csv(String path, {int maxRows = 2000}) =>
      _b.map('csv', {'path': path, 'maxRows': maxRows});

  Future<String> plain(String path) async => (await _b.call<String>('plain', {'path': path})) ?? '';
}

class SystemApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/system');

  Stream<Map<String, dynamic>> get events => _events('com.onyx.terminal/system_stream');

  Future<Map<String, dynamic>> device() => _b.map('device');

  Future<Map<String, dynamic>> snapshot() => _b.map('snapshot');

  Future<void> setInterval(int ms) => _b.run('setInterval', {'ms': ms});

  Future<List<Map<String, dynamic>>> interfaces() => _b.list('interfaces');

  Future<Map<String, dynamic>> dns(String host) => _b.map('dns', {'host': host});

  Future<Map<String, dynamic>> ping(String host, {int count = 4, int timeoutMs = 3000, int port = 443}) =>
      _b.map('ping', {'host': host, 'count': count, 'timeoutMs': timeoutMs, 'port': port});

  Future<Map<String, dynamic>> portScan(String id, String host, List<int> ports, {int timeoutMs = 800}) =>
      _b.map('portScan', {'id': id, 'host': host, 'ports': ports, 'timeoutMs': timeoutMs});

  Future<void> cancelTool(String id) => _b.run('cancelTool', {'id': id});

  Future<Map<String, dynamic>> http(String method, String url, {Map<String, String>? headers, String? body}) =>
      _b.map('http', {'method': method, 'url': url, 'headers': headers ?? <String, String>{}, 'body': body});

  Future<String> publicIp() async => (await _b.call<String>('publicIp')) ?? '';

  Future<List<String>> logs({int lines = 300}) async {
    final value = await _b.call<List<Object?>>('logs', {'lines': lines});
    return (value ?? <Object?>[]).map((e) => e.toString()).toList();
  }

  Future<void> clearLogs() => _b.run('clearLogs');
}

class ProcessApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/process');

  Stream<List<ProcessInfo>> get stream => _events('com.onyx.terminal/process_stream')
      .where((e) => e['type'] == 'processes')
      .map((e) => asMapList(e['items']).map(ProcessInfo.fromMap).toList());

  Future<List<ProcessInfo>> list() async => (await _b.list('list')).map(ProcessInfo.fromMap).toList();

  Future<void> signal(int pid, int signal) => _b.run('signal', {'pid': pid, 'signal': signal});

  Future<void> setInterval(int ms) => _b.run('setInterval', {'ms': ms});
}

class WindowApi {
  final _Bridge _b = _Bridge('com.onyx.terminal/window');

  Future<void> setSecure(bool enabled) => _b.run('setSecure', {'enabled': enabled});

  Future<void> setKeepScreenOn(bool enabled) => _b.run('setKeepScreenOn', {'enabled': enabled});

  Future<void> moveToBack() => _b.run('moveToBack');
}

class Api {
  Api()
      : auth = AuthApi(),
        terminal = TerminalApi(),
        sftp = SftpApi(),
        fs = FsApi(),
        editor = EditorApi(),
        viewer = ViewerApi(),
        system = SystemApi(),
        process = ProcessApi(),
        window = WindowApi();

  final AuthApi auth;
  final TerminalApi terminal;
  final SftpApi sftp;
  final FsApi fs;
  final EditorApi editor;
  final ViewerApi viewer;
  final SystemApi system;
  final ProcessApi process;
  final WindowApi window;
}
