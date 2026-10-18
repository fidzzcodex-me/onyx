import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/models.dart';

void main() {
  test('FileEntry dibaca dari peta native', () {
    final e = FileEntry.fromMap({'name': '.env', 'path': '/a/.env', 'isDir': false, 'size': 12, 'modified': 5, 'mode': 'rw-r--r--', 'isLink': false});
    expect(e.hidden, isTrue);
    expect(e.extension, '');
    expect(e.readable, isTrue);
  });

  test('TransferItem menghitung rasio dan status', () {
    final t = TransferItem.fromMap({'id': '1', 'name': 'x', 'total': 200, 'done': 50, 'state': 'running'});
    expect(t.ratio, 0.25);
    expect(t.active, isTrue);
    expect(t.finished, isFalse);
    final done = TransferItem.fromMap({'id': '2', 'name': 'y', 'total': 0, 'done': 0, 'state': 'done'});
    expect(done.ratio, 1);
  });

  test('ConnProfile bolak-balik lewat peta', () {
    final p = ConnProfile.fromMap({'id': 'a', 'name': 'Prod', 'protocol': 'sftp', 'host': 'h', 'port': 2222, 'username': 'u', 'authType': 'key'});
    expect(p.isSsh, isTrue);
    expect(p.toMap()['port'], 2222);
    expect(ConnProfile.fromMap({'id': 'b', 'protocol': 'ftp', 'host': 'h', 'username': 'u'}).isSsh, isFalse);
  });

  test('AppUser menghitung inisial', () {
    expect(const AppUser(id: '1', name: 'Fidzz Dev', email: 'a@b.c', isGuest: false).initials, 'FD');
    expect(const AppUser(id: '1', name: '', email: '', isGuest: true).initials, '?');
  });
}
