import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/tools/network_tools.dart';

void main() {
  test('daftar dan rentang port digabung, unik, dan terurut', () {
    expect(parsePorts('80, 22 443'), [22, 80, 443]);
    expect(parsePorts('8000-8003,8001'), [8000, 8001, 8002, 8003]);
  });

  test('masukan tidak valid ditolak dengan pesan', () {
    expect(() => parsePorts('abc'), throwsFormatException);
    expect(() => parsePorts('0'), throwsFormatException);
    expect(() => parsePorts('70000'), throwsFormatException);
    expect(() => parsePorts('90-80'), throwsFormatException);
  });

  test('batas jumlah port', () {
    expect(() => parsePorts('1-5000'), throwsFormatException);
  });
}
