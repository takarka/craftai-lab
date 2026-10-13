import 'dart:convert';
import 'dart:io';

import '../models/chat_conversation.dart';

/// Serializes writes and keeps the previous valid archive for recovery.
class ChatStorage {
  final Future<Directory> Function() directoryProvider;
  Future<void> _writes = Future.value();
  ChatStorage(this.directoryProvider);

  Future<File> _file() async {
    final directory = await directoryProvider();
    await directory.create(recursive: true);
    return File('${directory.path}/chats.json');
  }

  Future<ChatArchive?> load() async {
    final file = await _file();
    Object? lastError;
    for (final path in [file.path, '${file.path}.backup', '${file.path}.tmp']) {
      final candidate = File(path);
      if (!await candidate.exists()) continue;
      try {
        return ChatArchive.fromJson(
          jsonDecode(await candidate.readAsString()) as Map<String, dynamic>,
        );
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      throw FormatException('Не удалось прочитать историю чатов: $lastError');
    }
    return null;
  }

  Future<void> save(ChatArchive archive) {
    final encoded = jsonEncode(archive.toJson());
    final write = _writes.then((_) async {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      final backup = File('${file.path}.backup');
      await temp.writeAsString(encoded, flush: true);
      if (await file.exists()) {
        var valid = false;
        try {
          ChatArchive.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>,
          );
          valid = true;
        } catch (_) {
          /* Keep a valid recovery copy if the primary is corrupt. */
        }
        if (valid) {
          if (await backup.exists()) await backup.delete();
          await file.rename(backup.path);
        } else {
          await file.delete();
        }
      }
      await temp.rename(file.path);
    });
    _writes = write.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return write;
  }
}
