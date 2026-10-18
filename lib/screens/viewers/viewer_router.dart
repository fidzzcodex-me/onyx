import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/file_icons.dart';
import '../../core/models.dart';
import '../../state/providers.dart';
import '../../widgets/feedback.dart';
import '../editor/editor_screen.dart';
import '../editor/editor_source.dart';
import 'archive_viewer.dart';
import 'audio_viewer.dart';
import 'document_viewer.dart';
import 'hex_viewer.dart';
import 'image_viewer.dart';
import 'pdf_viewer.dart';
import 'video_viewer.dart';

Future<void> _push(BuildContext context, Widget screen) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

FileKind _kind(FileEntry e) => kindOf(isDir: e.isDir, ext: e.extension.toLowerCase(), mime: e.mime, isLink: false, name: e.name);

Future<void> openLocalFile(BuildContext context, WidgetRef ref, FileEntry entry, {List<FileEntry>? siblings}) async {
  final kind = _kind(entry);
  final list = siblings ?? const <FileEntry>[];
  switch (kind) {
    case FileKind.image:
      if (entry.extension.toLowerCase() == 'svg') {
        await openAsText(context, ref, entry);
        return;
      }
      final images = list.where((e) => _kind(e) == FileKind.image && e.extension.toLowerCase() != 'svg').toList();
      final index = images.indexWhere((e) => e.path == entry.path);
      await _push(context, index < 0 ? ImageViewerScreen(images: [entry], index: 0) : ImageViewerScreen(images: images, index: index));
    case FileKind.video:
      await _push(context, VideoViewerScreen(entry: entry));
    case FileKind.audio:
      final tracks = list.where((e) => _kind(e) == FileKind.audio).toList();
      final index = tracks.indexWhere((e) => e.path == entry.path);
      await _push(context, index < 0 ? AudioViewerScreen(tracks: [entry], index: 0) : AudioViewerScreen(tracks: tracks, index: index));
    case FileKind.pdf:
      await _push(context, PdfViewerScreen(entry: entry));
    case FileKind.archive:
      await _push(context, ArchiveViewerScreen(entry: entry));
    case FileKind.code:
    case FileKind.text:
      final ext = entry.extension.toLowerCase();
      if (ext == 'csv' || ext == 'tsv') {
        await _push(context, DocumentViewerScreen(entry: entry, kind: DocumentKind.csv));
      } else {
        await openAsText(context, ref, entry);
      }
    case FileKind.apk:
      await _external(context, ref, entry);
    case FileKind.document:
      await _external(context, ref, entry);
    case FileKind.link:
    case FileKind.folder:
      break;
    case FileKind.binary:
      await _binary(context, ref, entry);
  }
}

Future<void> _external(BuildContext context, WidgetRef ref, FileEntry entry) async {
  await runGuarded(context, () => ref.read(apiProvider).fs.open(entry.path, mime: entry.mime.isEmpty ? null : entry.mime));
}

Future<void> _binary(BuildContext context, WidgetRef ref, FileEntry entry) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: const Text('Buka dengan aplikasi lain'), onTap: () => Navigator.pop(ctx, 'external')),
          ListTile(title: const Text('Buka sebagai teks'), onTap: () => Navigator.pop(ctx, 'text')),
          ListTile(title: const Text('Buka di penampil hex'), onTap: () => Navigator.pop(ctx, 'hex')),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'external':
      await _external(context, ref, entry);
    case 'text':
      await openAsText(context, ref, entry);
    case 'hex':
      await openAsHex(context, entry);
  }
}

Future<void> openAsText(BuildContext context, WidgetRef ref, FileEntry entry) {
  return _push(context, EditorScreen(source: LocalEditorSource(entry.path)));
}

Future<void> openAsHex(BuildContext context, FileEntry entry) {
  return _push(context, HexViewerScreen(entry: entry));
}

Future<void> openRemoteText(BuildContext context, {required String sessionId, required String path, required ConnProfile profile}) {
  return _push(context, EditorScreen(source: RemoteEditorSource(sessionId: sessionId, path: path, profile: profile)));
}
