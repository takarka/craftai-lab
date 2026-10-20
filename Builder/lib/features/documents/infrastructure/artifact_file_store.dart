import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/document_models.dart';

/// Private on-device area for downloaded documents, one directory per owner
/// and artifact. A file under its final name exists only after it was verified;
/// everything before that is a `download.part`.
class ArtifactFileStore {
  ArtifactFileStore(this.rootProvider);

  /// e.g. `<app support>/artifact_downloads`.
  final Future<Directory> Function() rootProvider;

  String _segment(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<Directory> _ownerDir(String ownerId) async =>
      Directory(p.join((await rootProvider()).path, _segment(ownerId)));

  Future<Directory> _dir(String ownerId, String artifactId) async =>
      Directory(p.join((await _ownerDir(ownerId)).path, _segment(artifactId)));

  /// A safe local name that keeps the document's extension.
  static String localName(DocumentArtifact artifact) {
    final name = safeSourceFileName(artifact.fileName);
    final ext = '.${artifact.format.wire}';
    return name.toLowerCase().endsWith(ext) ? name : '$name$ext';
  }

  Future<File> partFile(String ownerId, String artifactId) async {
    final dir = await _dir(ownerId, artifactId);
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'download.part'));
  }

  Future<File> readyFile(String ownerId, DocumentArtifact artifact) async =>
      File(p.join((await _dir(ownerId, artifact.id)).path, localName(artifact)));

  Future<void> delete(String ownerId, String artifactId) async {
    final dir = await _dir(ownerId, artifactId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> deleteOwner(String ownerId) async {
    final dir = await _ownerDir(ownerId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes copies of artifacts that are no longer listed for [ownerId]
  /// (deleted or expired tasks) and every leftover partial download.
  Future<void> sweep(String ownerId, Set<String> keepArtifactIds) async {
    final dir = await _ownerDir(ownerId);
    if (!await dir.exists()) return;
    final keep = keepArtifactIds.map(_segment).toSet();
    await for (final entry in dir.list()) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (!keep.contains(name)) {
        await entry.delete(recursive: true);
        continue;
      }
      final part = File(p.join(entry.path, 'download.part'));
      if (await part.exists()) await part.delete();
    }
  }
}
