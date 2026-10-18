import 'format.dart';

Map<String, dynamic> asMap(Object? value) {
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is List) return value.map(asMap).toList();
  return <Map<String, dynamic>>[];
}

class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
    required this.mode,
    required this.isLink,
    this.mime = '',
    this.readable = true,
    this.writable = true,
  });

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int modified;
  final String mode;
  final bool isLink;
  final String mime;
  final bool readable;
  final bool writable;

  String get extension => extensionOf(name);
  bool get hidden => name.startsWith('.');

  factory FileEntry.fromMap(Map<String, dynamic> m) => FileEntry(
        name: (m['name'] ?? '') as String,
        path: (m['path'] ?? '') as String,
        isDir: (m['isDir'] ?? false) as bool,
        size: ((m['size'] ?? 0) as num).toInt(),
        modified: ((m['modified'] ?? 0) as num).toInt(),
        mode: (m['mode'] ?? '') as String,
        isLink: (m['isLink'] ?? false) as bool,
        mime: (m['mime'] ?? '') as String,
        readable: (m['readable'] ?? true) as bool,
        writable: (m['writable'] ?? true) as bool,
      );
}

class StorageRoot {
  const StorageRoot({
    required this.id,
    required this.title,
    required this.kind,
    required this.path,
    required this.total,
    required this.free,
  });

  final String id;
  final String title;
  final String kind;
  final String path;
  final int total;
  final int free;

  double get usedRatio => total <= 0 ? 0 : ((total - free) / total).clamp(0.0, 1.0);

  factory StorageRoot.fromMap(Map<String, dynamic> m) => StorageRoot(
        id: m['id'] as String,
        title: m['title'] as String,
        kind: m['kind'] as String,
        path: m['path'] as String,
        total: ((m['total'] ?? 0) as num).toInt(),
        free: ((m['free'] ?? 0) as num).toInt(),
      );
}

class ConnProfile {
  const ConnProfile({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    this.keyId,
    this.proxyType = 'none',
    this.proxyHost,
    this.proxyPort = 0,
    this.jumpId,
    this.keepAlive = 15,
    this.timeoutSec = 20,
    this.initialPath,
    this.hasSecret = false,
    this.lastUsed = 0,
  });

  final String id;
  final String name;
  final String protocol;
  final String host;
  final int port;
  final String username;
  final String authType;
  final String? keyId;
  final String proxyType;
  final String? proxyHost;
  final int proxyPort;
  final String? jumpId;
  final int keepAlive;
  final int timeoutSec;
  final String? initialPath;
  final bool hasSecret;
  final int lastUsed;

  bool get isSsh => protocol == 'sftp' || protocol == 'scp';

  factory ConnProfile.fromMap(Map<String, dynamic> m) => ConnProfile(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        protocol: (m['protocol'] ?? 'sftp') as String,
        host: (m['host'] ?? '') as String,
        port: ((m['port'] ?? 22) as num).toInt(),
        username: (m['username'] ?? '') as String,
        authType: (m['authType'] ?? 'password') as String,
        keyId: m['keyId'] as String?,
        proxyType: (m['proxyType'] ?? 'none') as String,
        proxyHost: m['proxyHost'] as String?,
        proxyPort: ((m['proxyPort'] ?? 0) as num).toInt(),
        jumpId: m['jumpId'] as String?,
        keepAlive: ((m['keepAlive'] ?? 15) as num).toInt(),
        timeoutSec: ((m['timeoutSec'] ?? 20) as num).toInt(),
        initialPath: m['initialPath'] as String?,
        hasSecret: (m['hasSecret'] ?? false) as bool,
        lastUsed: ((m['lastUsed'] ?? 0) as num).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'protocol': protocol,
        'host': host,
        'port': port,
        'username': username,
        'authType': authType,
        'keyId': keyId,
        'proxyType': proxyType,
        'proxyHost': proxyHost,
        'proxyPort': proxyPort,
        'jumpId': jumpId,
        'keepAlive': keepAlive,
        'timeoutSec': timeoutSec,
        'initialPath': initialPath,
      };
}

class SshKey {
  const SshKey({
    required this.id,
    required this.name,
    required this.type,
    required this.publicKey,
    required this.fingerprint,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String type;
  final String publicKey;
  final String fingerprint;
  final int createdAt;

  factory SshKey.fromMap(Map<String, dynamic> m) => SshKey(
        id: m['id'] as String,
        name: m['name'] as String,
        type: m['type'] as String,
        publicKey: m['publicKey'] as String,
        fingerprint: m['fingerprint'] as String,
        createdAt: ((m['createdAt'] ?? 0) as num).toInt(),
      );
}

class TransferItem {
  const TransferItem({
    required this.id,
    required this.direction,
    required this.name,
    required this.localPath,
    required this.remotePath,
    required this.total,
    required this.done,
    required this.state,
    required this.speed,
    required this.etaSec,
    this.error,
  });

  final String id;
  final String direction;
  final String name;
  final String localPath;
  final String remotePath;
  final int total;
  final int done;
  final String state;
  final double speed;
  final int etaSec;
  final String? error;

  double get ratio => total <= 0 ? (state == 'done' ? 1 : 0) : (done / total).clamp(0.0, 1.0);
  bool get active => state == 'running' || state == 'queued';
  bool get finished => state == 'done' || state == 'error' || state == 'canceled';

  factory TransferItem.fromMap(Map<String, dynamic> m) => TransferItem(
        id: m['id'] as String,
        direction: (m['direction'] ?? 'download') as String,
        name: (m['name'] ?? '') as String,
        localPath: (m['localPath'] ?? '') as String,
        remotePath: (m['remotePath'] ?? '') as String,
        total: ((m['total'] ?? 0) as num).toInt(),
        done: ((m['done'] ?? 0) as num).toInt(),
        state: (m['state'] ?? 'queued') as String,
        speed: ((m['speed'] ?? 0) as num).toDouble(),
        etaSec: ((m['etaSec'] ?? -1) as num).toInt(),
        error: m['error'] as String?,
      );
}

class AppUser {
  const AppUser({required this.id, required this.name, required this.email, required this.isGuest});

  final String id;
  final String name;
  final String email;
  final bool isGuest;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        isGuest: (m['isGuest'] ?? false) as bool,
      );
}

class TermInfo {
  const TermInfo({required this.id, required this.kind, required this.title, required this.alive, this.cwd});

  final int id;
  final String kind;
  final String title;
  final bool alive;
  final String? cwd;

  factory TermInfo.fromMap(Map<String, dynamic> m) => TermInfo(
        id: (m['id'] as num).toInt(),
        kind: (m['kind'] ?? 'local') as String,
        title: (m['title'] ?? 'Shell') as String,
        alive: (m['alive'] ?? true) as bool,
        cwd: m['cwd'] as String?,
      );
}

class ProcessInfo {
  const ProcessInfo({
    required this.pid,
    required this.ppid,
    required this.name,
    required this.cmd,
    required this.state,
    required this.threads,
    required this.rssKb,
    required this.cpu,
    required this.own,
  });

  final int pid;
  final int ppid;
  final String name;
  final String cmd;
  final String state;
  final int threads;
  final int rssKb;
  final double cpu;
  final bool own;

  factory ProcessInfo.fromMap(Map<String, dynamic> m) => ProcessInfo(
        pid: (m['pid'] as num).toInt(),
        ppid: ((m['ppid'] ?? 0) as num).toInt(),
        name: (m['name'] ?? '') as String,
        cmd: (m['cmd'] ?? '') as String,
        state: (m['state'] ?? '') as String,
        threads: ((m['threads'] ?? 1) as num).toInt(),
        rssKb: ((m['rssKb'] ?? 0) as num).toInt(),
        cpu: ((m['cpu'] ?? 0) as num).toDouble(),
        own: (m['own'] ?? false) as bool,
      );

  String get memory => formatBytes(rssKb * 1024);
}
