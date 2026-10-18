import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/format.dart';

void main() {
  group('formatBytes', () {
    test('byte kecil tanpa desimal', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('satuan naik tiap 1024', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    });

    test('nilai negatif jadi strip', () {
      expect(formatBytes(-1), '-');
    });
  });

  group('jalur', () {
    test('baseName', () {
      expect(baseName('/a/b/c.txt'), 'c.txt');
      expect(baseName('/a/b/'), 'b');
      expect(baseName('/'), '/');
      expect(baseName('file'), 'file');
    });

    test('parentOf', () {
      expect(parentOf('/a/b/c.txt'), '/a/b');
      expect(parentOf('/a'), '/');
      expect(parentOf('/'), '/');
    });

    test('joinPath tidak menggandakan garis miring', () {
      expect(joinPath('/a', 'b'), '/a/b');
      expect(joinPath('/a/', 'b'), '/a/b');
    });

    test('extensionOf huruf kecil dan abaikan dotfile', () {
      expect(extensionOf('/x/Foto.JPG'), 'jpg');
      expect(extensionOf('/x/.bashrc'), '');
      expect(extensionOf('/x/arsip.tar.gz'), 'gz');
    });
  });

  group('formatEta', () {
    test('rentang', () {
      expect(formatEta(-1), '-');
      expect(formatEta(45), '45 dtk');
      expect(formatEta(125), '2 mnt 5 dtk');
      expect(formatEta(7260), '2 j 1 mnt');
    });
  });
}
