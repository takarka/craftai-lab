import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Note model stored in private workspace area (F14-06).
class NoteItem {
  final String id;
  final String ownerId;
  final String title;
  final String content;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  const NoteItem({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.content,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'content': content,
      'created_at_utc': createdAtUtc.toIso8601String(),
      'updated_at_utc': updatedAtUtc.toIso8601String(),
    };
  }

  factory NoteItem.fromMap(Map<String, dynamic> map) {
    return NoteItem(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      createdAtUtc: DateTime.tryParse(map['created_at_utc'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      updatedAtUtc: DateTime.tryParse(map['updated_at_utc'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

/// Adapter for assistant private notes with size checks and safe naming (F14-06).
class NotesAdapter {
  final String? baseStorageDir;
  final Map<String, Map<String, NoteItem>> _inMemoryFallback = {};

  static const int maxNoteSizeBytes = 100 * 1024; // 100 KB limit per note

  NotesAdapter({String? baseStorageDir, Directory? rootDirectory})
      : baseStorageDir = baseStorageDir ?? rootDirectory?.path;

  Directory? _getNotesDir(String ownerId) {
    if (baseStorageDir == null) return null;
    final sanitizedOwner = ownerId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return Directory(p.join(baseStorageDir!, 'workspaces', sanitizedOwner, 'notes'));
  }

  Future<NoteItem?> getNote({
    required String ownerId,
    required String noteId,
  }) async {
    final sanitizedNoteId = noteId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    if (sanitizedNoteId.isEmpty) return null;

    final dir = _getNotesDir(ownerId);
    if (dir != null && dir.existsSync()) {
      final file = File(p.join(dir.path, '$sanitizedNoteId.json'));
      if (file.existsSync()) {
        try {
          final content = file.readAsStringSync();
          final map = jsonDecode(content) as Map<String, dynamic>;
          return NoteItem.fromMap(map);
        } catch (_) {}
      }
      return null;
    } else {
      return _inMemoryFallback[ownerId]?[sanitizedNoteId];
    }
  }

  Future<NoteItem> createNote({
    required String ownerId,
    required String title,
    required String content,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedContent = content.trim();

    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Заголовок заметки не может быть пустым');
    }

    final bytes = utf8.encode(trimmedContent);
    if (bytes.length > maxNoteSizeBytes) {
      throw ArgumentError('Превышен максимальный размер заметки (100 КБ)');
    }

    final now = DateTime.now().toUtc();
    final noteId = 'note_${now.millisecondsSinceEpoch}_${trimmedTitle.hashCode.abs() % 1000}';

    final note = NoteItem(
      id: noteId,
      ownerId: ownerId,
      title: trimmedTitle,
      content: trimmedContent,
      createdAtUtc: now,
      updatedAtUtc: now,
    );

    final dir = _getNotesDir(ownerId);
    if (dir != null) {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeFileName = '$noteId.json';
      final file = File(p.join(dir.path, safeFileName));
      await file.writeAsString(jsonEncode(note.toMap()), flush: true);
    } else {
      final userNotes = _inMemoryFallback.putIfAbsent(ownerId, () => {});
      userNotes[noteId] = note;
    }

    return note;
  }

  Future<List<NoteItem>> listNotes(String ownerId, {String? query}) async {
    final notes = <NoteItem>[];

    final dir = _getNotesDir(ownerId);
    if (dir != null && dir.existsSync()) {
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      for (final file in files) {
        try {
          final content = file.readAsStringSync();
          final map = jsonDecode(content) as Map<String, dynamic>;
          notes.add(NoteItem.fromMap(map));
        } catch (_) {}
      }
    } else {
      final userNotes = _inMemoryFallback[ownerId] ?? {};
      notes.addAll(userNotes.values);
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = query.toLowerCase().trim();
      return notes.where((n) {
        return n.title.toLowerCase().contains(q) || n.content.toLowerCase().contains(q);
      }).toList();
    }

    return notes;
  }

  Future<bool> deleteNote({
    required String ownerId,
    required String noteId,
  }) async {
    final sanitizedNoteId = noteId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    final dir = _getNotesDir(ownerId);
    if (dir != null && dir.existsSync()) {
      final file = File(p.join(dir.path, '$sanitizedNoteId.json'));
      if (file.existsSync()) {
        file.deleteSync();
        return true;
      }
      return false;
    } else {
      final removed = _inMemoryFallback[ownerId]?.remove(noteId);
      return removed != null;
    }
  }
}
