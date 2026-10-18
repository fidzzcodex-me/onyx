import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/highlighter.dart';

const _base = TextStyle(color: Colors.white);

String _join(List<TextSpan> spans) => spans.map((s) => s.text ?? '').join();

Color? _colorOf(List<TextSpan> spans, String text) {
  for (final s in spans) {
    if (s.text == text) return s.style?.color;
  }
  return null;
}

void main() {
  test('teks asli tidak berubah setelah disorot', () {
    const source = 'fun main() {\n  val x = "halo"\n  return 42\n}\n';
    final spans = Highlighter.spans(source, 'kotlin', SyntaxColors.dark, _base);
    expect(_join(spans), source);
  });

  test('kata kunci, string, angka, dan komentar diwarnai', () {
    const source = 'val a = "x" + 7\nvar b = 1';
    final spans = Highlighter.spans(source, 'kotlin', SyntaxColors.dark, _base);
    expect(_colorOf(spans, 'val'), SyntaxColors.dark.keyword);
    expect(_colorOf(spans, '"x"'), SyntaxColors.dark.string);
    expect(_colorOf(spans, '7'), SyntaxColors.dark.number);
  });

  test('komentar baris dan blok', () {
    const source = 'a = 1 # catatan\nb = 2';
    final py = Highlighter.spans(source, 'python', SyntaxColors.dark, _base);
    expect(_colorOf(py, '# catatan'), SyntaxColors.dark.comment);
    const block = 'x /* satu\ndua */ y';
    final c = Highlighter.spans(block, 'c', SyntaxColors.dark, _base);
    expect(_colorOf(c, '/* satu\ndua */'), SyntaxColors.dark.comment);
    expect(_join(c), block);
  });

  test('kunci JSON dibedakan dari nilai string', () {
    const source = '{"nama": "onyx"}';
    final spans = Highlighter.spans(source, 'json', SyntaxColors.dark, _base);
    expect(_colorOf(spans, '"nama"'), SyntaxColors.dark.key);
    expect(_colorOf(spans, '"onyx"'), SyntaxColors.dark.string);
  });

  test('diff mewarnai baris tambah dan hapus', () {
    const source = '--- a\n+++ b\n+baru\n-lama\n sama';
    final spans = Highlighter.spans(source, 'diff', SyntaxColors.dark, _base);
    expect(_join(spans), source);
    expect(_colorOf(spans, '+baru\n'), SyntaxColors.dark.added);
    expect(_colorOf(spans, '-lama\n'), SyntaxColors.dark.removed);
  });

  test('berkas besar dilewati tanpa penyorotan', () {
    final source = 'a' * (Highlighter.maxChars + 1);
    final spans = Highlighter.spans(source, 'kotlin', SyntaxColors.dark, _base);
    expect(spans.length, 1);
  });

  test('bahasa tidak dikenal dikembalikan polos', () {
    final spans = Highlighter.spans('apa saja', 'plaintext', SyntaxColors.dark, _base);
    expect(spans.length, 1);
    expect(Highlighter.supports('plaintext'), isFalse);
    expect(Highlighter.supports('py'), isTrue);
  });
}
