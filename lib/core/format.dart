String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes < 0) return '-';
  if (bytes < 1024) return '${bytes.toInt()} B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  double value = bytes / 1024;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = value >= 100 ? 0 : decimals;
  return '${value.toStringAsFixed(digits)} ${units[index]}';
}

String formatSpeed(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

String formatEta(int seconds) {
  if (seconds < 0) return '-';
  if (seconds < 60) return '$seconds dtk';
  if (seconds < 3600) return '${seconds ~/ 60} mnt ${seconds % 60} dtk';
  return '${seconds ~/ 3600} j ${(seconds % 3600) ~/ 60} mnt';
}

String formatUptime(int ms) {
  final d = Duration(milliseconds: ms);
  if (d.inDays > 0) return '${d.inDays} hari ${d.inHours.remainder(24)} jam';
  if (d.inHours > 0) return '${d.inHours} jam ${d.inMinutes.remainder(60)} mnt';
  return '${d.inMinutes} mnt';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String formatDate(int millis) {
  if (millis <= 0) return '-';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Hari ini $hm';
  if (d.year == now.year) return '${d.day} ${_months[d.month - 1]} $hm';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String formatDateFull(int millis) {
  if (millis <= 0) return '-';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  return '${d.day} ${_months[d.month - 1]} ${d.year} $hm';
}

String baseName(String path) {
  final trimmed = path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = trimmed.lastIndexOf('/');
  return i < 0 ? trimmed : (i == trimmed.length - 1 ? '/' : trimmed.substring(i + 1));
}

String parentOf(String path) {
  final trimmed = path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = trimmed.lastIndexOf('/');
  if (i <= 0) return '/';
  return trimmed.substring(0, i);
}

String joinPath(String base, String name) => base.endsWith('/') ? '$base$name' : '$base/$name';

String extensionOf(String path) {
  final name = baseName(path);
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
}

String shortenPath(String path, {int max = 38}) {
  if (path.length <= max) return path;
  final parts = path.split('/').where((e) => e.isNotEmpty).toList();
  if (parts.length <= 2) return '...${path.substring(path.length - max + 3)}';
  return '/${parts.first}/.../${parts.last}';
}

String percent(num value) => '${value.clamp(0, 100).toStringAsFixed(value >= 10 ? 0 : 1)}%';
