import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'tokens.dart';

enum FileKind { folder, image, video, audio, pdf, archive, code, text, document, apk, binary, link }

const _image = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg', 'ico'};
const _video = {'mp4', 'mkv', 'webm', 'avi', 'mov', '3gp', 'm4v', 'ts'};
const _audio = {'mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'opus', 'amr'};
const _archive = {'zip', 'tar', 'gz', 'tgz', 'bz2', 'tbz2', 'xz', 'txz', '7z', 'rar', 'jar', 'aar'};
const _code = {
  'kt', 'kts', 'java', 'dart', 'js', 'mjs', 'cjs', 'jsx', 'tsx', 'py', 'rb', 'go', 'rs', 'c', 'h', 'cpp', 'hpp', 'cc',
  'cs', 'swift', 'php', 'lua', 'sh', 'bash', 'zsh', 'sql', 'gradle', 'html', 'htm', 'css', 'scss', 'vue', 'xml',
  'json', 'yaml', 'yml', 'toml', 'ini', 'conf', 'cfg', 'properties', 'diff', 'patch', 'cmake', 'make'
};
const _text = {'txt', 'md', 'markdown', 'log', 'csv', 'tsv', 'env', 'gitignore', 'rst', 'tex'};
const _doc = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'epub'};

FileKind kindOf({required bool isDir, required String ext, String mime = '', bool isLink = false, String name = ''}) {
  if (isDir) return FileKind.folder;
  if (isLink) return FileKind.link;
  if (_image.contains(ext) || mime.startsWith('image/')) return FileKind.image;
  if (_video.contains(ext) || mime.startsWith('video/')) return FileKind.video;
  if (_audio.contains(ext) || mime.startsWith('audio/')) return FileKind.audio;
  if (ext == 'pdf') return FileKind.pdf;
  if (ext == 'apk') return FileKind.apk;
  if (_archive.contains(ext)) return FileKind.archive;
  if (_code.contains(ext)) return FileKind.code;
  if (_text.contains(ext) || mime.startsWith('text/')) return FileKind.text;
  if (_doc.contains(ext)) return FileKind.document;
  const plainNames = {'dockerfile', 'makefile', '.bashrc', '.profile', '.zshrc', '.gitignore', 'readme', 'license'};
  if (plainNames.contains(name.toLowerCase())) return FileKind.text;
  return FileKind.binary;
}

IconData iconFor(FileKind kind) {
  switch (kind) {
    case FileKind.folder:
      return FontAwesomeIcons.folder;
    case FileKind.image:
      return FontAwesomeIcons.image;
    case FileKind.video:
      return FontAwesomeIcons.film;
    case FileKind.audio:
      return FontAwesomeIcons.music;
    case FileKind.pdf:
      return FontAwesomeIcons.filePdf;
    case FileKind.archive:
      return FontAwesomeIcons.boxArchive;
    case FileKind.code:
      return FontAwesomeIcons.code;
    case FileKind.text:
      return FontAwesomeIcons.fileLines;
    case FileKind.document:
      return FontAwesomeIcons.fileWord;
    case FileKind.apk:
      return FontAwesomeIcons.android;
    case FileKind.link:
      return FontAwesomeIcons.link;
    case FileKind.binary:
      return FontAwesomeIcons.file;
  }
}

Color colorFor(FileKind kind, OnyxPalette p) {
  switch (kind) {
    case FileKind.folder:
      return p.accent;
    case FileKind.image:
      return p.info;
    case FileKind.video:
      return const Color(0xFFBA68C8);
    case FileKind.audio:
      return p.warning;
    case FileKind.pdf:
      return p.error;
    case FileKind.archive:
      return p.warning;
    case FileKind.code:
      return p.success;
    case FileKind.apk:
      return p.success;
    default:
      return p.textSecondary;
  }
}
