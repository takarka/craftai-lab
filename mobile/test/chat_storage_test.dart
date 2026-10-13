import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/chat_conversation.dart';
import 'package:mobile/models/chat_message.dart';
import 'package:mobile/services/chat_storage.dart';

ChatArchive archive(String text, {bool generating = false}) => ChatArchive(
  activeId: 'chat',
  contextSize: 4096,
  conversations: [
    ChatConversation(
      id: 'chat',
      updatedAt: DateTime(2026),
      messages: [
        ChatMessage(
          id: 'u',
          text: 'Меня зовут Арка',
          isUser: true,
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: 'a',
          text: text,
          reasoning: 'Мысли модели',
          isUser: false,
          timestamp: DateTime(2026),
          isGenerating: generating,
          contextText: 'web context',
        ),
      ],
      summary: 'Пользователь Арка',
      summarizedThroughId: 'a',
    ),
  ],
);

void main() {
  late Directory directory;
  late ChatStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mobile-chat-storage-');
    storage = ChatStorage(() async => directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'restores messages, reasoning, summary, active chat and context size',
    () async {
      expect(await storage.load(), isNull);
      await storage.save(archive('Ответ'));
      final restored = (await ChatStorage(() async => directory).load())!;
      expect(restored.contextSize, 4096);
      expect(restored.activeId, 'chat');
      expect(restored.conversations.single.title, 'Меня зовут Арка');
      expect(restored.conversations.single.summary, 'Пользователь Арка');
      final message = restored.conversations.single.messages.last;
      expect(message.text, 'Ответ');
      expect(message.reasoning, 'Мысли модели');
      expect(message.contextText, 'web context');
    },
  );

  test('restored partial generation is marked interrupted', () async {
    await storage.save(archive('Часть ответа', generating: true));
    final reply = (await storage.load())!.conversations.single.messages.last;
    expect(reply.isGenerating, isFalse);
    expect(reply.text, 'Часть ответа');
    expect(reply.error, contains('прервана'));
  });

  test(
    'queued saves cannot overwrite newer messages with an old snapshot',
    () async {
      await Future.wait([
        storage.save(archive('Old')),
        storage.save(archive('Newest')),
      ]);
      expect(
        (await storage.load())!.conversations.single.messages.last.text,
        'Newest',
      );
    },
  );

  test('recovers backup if primary file is corrupt', () async {
    await storage.save(archive('Backup'));
    await storage.save(archive('Latest'));
    await File('${directory.path}/chats.json').writeAsString('{invalid');
    expect(
      (await storage.load())!.conversations.single.messages.last.text,
      'Backup',
    );
    await storage.save(archive('Recovered'));
    expect(
      (await storage.load())!.conversations.single.messages.last.text,
      'Recovered',
    );
  });

  test(
    'recovers flushed temporary archive after interrupted first save',
    () async {
      await File('${directory.path}/chats.json.tmp')
          .writeAsString(jsonEncode(archive('Temporary').toJson()));
      expect(
        (await storage.load())!.conversations.single.messages.last.text,
        'Temporary',
      );
    },
  );

  test('reports unreadable archives without overwriting originals', () async {
    final file = File('${directory.path}/chats.json');
    await file.writeAsString('corrupt');
    await expectLater(storage.load(), throwsFormatException);
    expect(await file.readAsString(), 'corrupt');
  });
}
