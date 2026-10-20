import 'dart:convert';
import 'dart:io';
import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/assistant/presentation/assistant_chat_page.dart';
import 'package:builder/features/chat/chat_providers.dart';
import 'package:builder/features/chat/domain/chat_message.dart';
import 'package:builder/features/chat/domain/chat_stream_event.dart';
import 'package:builder/features/chat/domain/context_assembler.dart';
import 'package:builder/features/chat/domain/conversation.dart';
import 'package:builder/features/chat/infrastructure/chat_stream_client.dart';
import 'package:builder/features/chat/infrastructure/persistent_chat_repository.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/policy/domain/policy_repository.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockPolicyRepository implements PolicyRepository {
  bool acknowledged = false;

  @override
  Future<bool> isPolicyAcknowledged({
    required String ownerId,
    required String policyId,
  }) async {
    return acknowledged;
  }

  @override
  Future<void> acknowledgePolicy({
    required String ownerId,
    required String policyId,
    required String policyVersion,
  }) async {
    acknowledged = true;
  }

  @override
  Future<PolicyAcknowledgment?> getAcknowledgment({
    required String ownerId,
    required String policyId,
  }) async {
    if (acknowledged) {
      return PolicyAcknowledgment(
        ownerId: ownerId,
        policyId: policyId,
        policyVersion: 'v1.0',
        acknowledgedAtUtc: DateTime.now().toUtc(),
      );
    }
    return null;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('F07-02: Conversation & Message CRUD with Retention Policy', () {
    test(
      'persists conversation and messages in SQLite for persistent policy',
      () async {
        final dbFactory = databaseFactoryFfi;
        final tempDir = Directory.systemTemp.createTempSync('f07_test_db_');
        final dbPath = p.join(tempDir.path, 'builder_f07_test.db');
        final storageDb = StorageDatabase(
          databasePath: dbPath,
          databaseFactory: dbFactory,
        );
        await storageDb.open();

        // Seed workspace for foreign key
        await storageDb.db.insert(StorageSchemaV1.tableWorkspaces, {
          'owner_id': 'owner_persistent_1',
          'installation_id': 'inst_1',
          'schema_version': 1,
          'workspace_epoch': 1,
          'created_at_utc': DateTime.now().toUtc().toIso8601String(),
          'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
        });

        final repo = PersistentChatRepository(database: storageDb);

        // Create persistent conversation
        final conv = await repo.createConversation(
          ownerId: 'owner_persistent_1',
          title: 'Урок физики',
          retentionPolicy: RetentionPolicy.persistent,
        );
        expect(conv.isEphemeral, isFalse);

        final userMsg = ChatMessage(
          id: 'msg_1',
          conversationId: conv.id,
          ownerId: 'owner_persistent_1',
          role: MessageRole.user,
          content: 'Что такое электрический ток?',
          status: MessageStatus.completed,
          createdAtUtc: DateTime.now().toUtc(),
        );
        await repo.saveMessage(userMsg);

        final loadedMessages = await repo.getMessages(conversationId: conv.id);
        expect(loadedMessages, hasLength(1));
        expect(
          loadedMessages.first.content,
          equals('Что такое электрический ток?'),
        );

        // Verify in raw SQLite
        final rawConv = await storageDb.db.query(
          StorageSchemaV1.tableConversations,
        );
        expect(rawConv, hasLength(1));
        final rawMsgs = await storageDb.db.query(StorageSchemaV1.tableMessages);
        expect(rawMsgs, hasLength(1));

        await storageDb.close();
        tempDir.deleteSync(recursive: true);
      },
    );

    test(
      'omits messages from SQLite when retention policy is ephemeral',
      () async {
        final dbFactory = databaseFactoryFfi;
        final tempDir = Directory.systemTemp.createTempSync(
          'f07_ephemeral_db_',
        );
        final dbPath = p.join(tempDir.path, 'builder_f07_ephemeral.db');
        final storageDb = StorageDatabase(
          databasePath: dbPath,
          databaseFactory: dbFactory,
        );
        await storageDb.open();

        final repo = PersistentChatRepository(database: storageDb);

        // Create ephemeral conversation
        final conv = await repo.createConversation(
          ownerId: 'owner_ephemeral_1',
          title: 'Секретный вопрос',
          retentionPolicy: RetentionPolicy.ephemeral,
        );
        expect(conv.isEphemeral, isTrue);

        final userMsg = ChatMessage(
          id: 'msg_e1',
          conversationId: conv.id,
          ownerId: 'owner_ephemeral_1',
          role: MessageRole.user,
          content: 'Временный текст',
          status: MessageStatus.completed,
          createdAtUtc: DateTime.now().toUtc(),
        );
        await repo.saveMessage(userMsg);

        // In-memory access works
        final inMemMessages = await repo.getMessages(conversationId: conv.id);
        expect(inMemMessages, hasLength(1));
        expect(inMemMessages.first.content, equals('Временный текст'));

        // SQLite tables remain completely empty!
        final rawConv = await storageDb.db.query(
          StorageSchemaV1.tableConversations,
        );
        expect(rawConv, isEmpty);
        final rawMsgs = await storageDb.db.query(StorageSchemaV1.tableMessages);
        expect(rawMsgs, isEmpty);

        await storageDb.close();
        tempDir.deleteSync(recursive: true);
      },
    );
  });

  group('F07-03 to F07-05: ContextAssembler & Token Budget Constraints', () {
    test(
      'enforces model contextWindow budget and reserves tokens for response',
      () {
        final assembler = const ContextAssembler(defaultReservedTokens: 100);

        final history = <ChatMessage>[
          ChatMessage(
            id: '1',
            conversationId: 'c1',
            ownerId: 'u1',
            role: MessageRole.user,
            content: 'Старое сообщение номер 1 ' * 10,
            status: MessageStatus.completed,
            createdAtUtc: DateTime.now().toUtc(),
          ),
          ChatMessage(
            id: '2',
            conversationId: 'c1',
            ownerId: 'u1',
            role: MessageRole.assistant,
            content: 'Старый ответ номер 2 ' * 10,
            status: MessageStatus.completed,
            createdAtUtc: DateTime.now().toUtc(),
          ),
          ChatMessage(
            id: '3',
            conversationId: 'c1',
            ownerId: 'u1',
            role: MessageRole.user,
            content: 'Свежее сообщение номер 3',
            status: MessageStatus.completed,
            createdAtUtc: DateTime.now().toUtc(),
          ),
        ];

        // Small contextWindow (150 tokens) with 100 reserved -> only 50 tokens available for context!
        final manifest = assembler.assemble(
          manifestId: 'man_1',
          requestId: 'req_1',
          category: 'fast',
          catalogRevision: 'rev-1',
          contextWindow: 150,
          reservedTokens: 100,
          conversationHistory: history,
          userPrompt: 'Новый вопрос',
        );

        expect(manifest.reservedTokens, equals(100));
        expect(manifest.messages.last['content'], equals('Новый вопрос'));
        // Oldest message (1) should be pruned because of budget limitation
        expect(
          manifest.messages.any((m) => m['content']!.contains('номер 1')),
          isFalse,
        );
      },
    );

    test('creates immutable snapshot manifest', () {
      final assembler = const ContextAssembler();
      final manifest = assembler.assemble(
        manifestId: 'man_snapshot',
        requestId: 'req_snapshot',
        category: 'standard',
        catalogRevision: '2026-03-31-01',
        contextWindow: 128000,
        activeInstruction: 'Всегда отвечай вежливо',
        memoryFacts: ['Учитель преподает физику'],
        conversationHistory: const [],
        userPrompt: 'Привет!',
      );

      expect(manifest.activeInstruction, equals('Всегда отвечай вежливо'));
      expect(manifest.memoryFacts, contains('Учитель преподает физику'));
      expect(manifest.messages.first['role'], equals('system'));
      expect(
        manifest.messages.first['content'],
        contains('Всегда отвечай вежливо'),
      );
      expect(manifest.messages.last['role'], equals('user'));
    });
  });

  group('F07-06 & F07-08: Streaming Parser, Cancellation and Error Handling', () {
    test('parses SSE events: start, text_delta, usage, terminal', () async {
      final tokenStorage = InMemorySecureTokenStorage();
      await tokenStorage.writeSession(
        ownerId: 'owner_stream_test',
        tokens: AuthTokens(
          accessToken: 'valid_token_123',
          refreshToken: 'refresh_123',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      final ssePayload =
          'event: start\nid: evt_1\ndata: {"type":"start","requestId":"req_s1","sequence":1,"eventId":"evt_1","modelId":"google/gemini-2.5-flash"}\n\n'
          'event: text_delta\nid: evt_2\ndata: {"type":"text_delta","requestId":"req_s1","sequence":2,"eventId":"evt_2","text":"Электрический "}\n\n'
          'event: text_delta\nid: evt_3\ndata: {"type":"text_delta","requestId":"req_s1","sequence":3,"eventId":"evt_3","text":"ток"}\n\n'
          'event: terminal\nid: evt_4\ndata: {"type":"terminal","requestId":"req_s1","sequence":4,"eventId":"evt_4","state":"completed","finishReason":"stop"}\n\n';

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(ssePayload),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final streamClient = ChatStreamClient(
        tokenStorage: tokenStorage,
        client: mockClient,
      );

      final events = await streamClient
          .streamCompletion(
            ownerId: 'owner_stream_test',
            category: 'fast',
            catalogRevision: 'rev-1',
            messages: [
              {'role': 'user', 'content': 'Test'},
            ],
            requestId: 'req_s1',
          )
          .toList();

      expect(events, hasLength(4));
      expect(events[0], isA<StartStreamEvent>());
      expect(
        (events[0] as StartStreamEvent).modelId,
        equals('google/gemini-2.5-flash'),
      );
      expect(events[1], isA<TextDeltaStreamEvent>());
      expect(
        (events[1] as TextDeltaStreamEvent).text,
        equals('Электрический '),
      );
      expect(events[2], isA<TextDeltaStreamEvent>());
      expect((events[2] as TextDeltaStreamEvent).text, equals('ток'));
      expect(events[3], isA<TerminalStreamEvent>());
      expect((events[3] as TerminalStreamEvent).isCompleted, isTrue);
    });

    test('cancellation triggers interrupted terminal event', () async {
      final tokenStorage = InMemorySecureTokenStorage();
      await tokenStorage.writeSession(
        ownerId: 'owner_cancel_test',
        tokens: AuthTokens(
          accessToken: 'valid_token_123',
          refreshToken: 'refresh_123',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      final cancelToken = ChatCancellationToken();

      final mockClient = MockClient((request) async {
        final ssePayload =
            'event: text_delta\nid: evt_1\ndata: {"type":"text_delta","requestId":"req_c1","sequence":1,"eventId":"evt_1","text":"Первая дельта"}\n\n';
        return http.Response.bytes(
          utf8.encode(ssePayload),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final streamClient = ChatStreamClient(
        tokenStorage: tokenStorage,
        client: mockClient,
      );

      final stream = streamClient.streamCompletion(
        ownerId: 'owner_cancel_test',
        category: 'fast',
        catalogRevision: 'rev-1',
        messages: [
          {'role': 'user', 'content': 'Test'},
        ],
        requestId: 'req_c1',
        cancellationToken: cancelToken,
      );

      final events = <StreamEvent>[];
      await for (final event in stream) {
        events.add(event);
        if (event is TextDeltaStreamEvent) {
          cancelToken.cancel();
        }
      }

      expect(
        events.any((e) => e is TerminalStreamEvent && e.isInterrupted),
        isTrue,
      );
    });

    test('maps 503 MODEL_UNAVAILABLE error correctly', () async {
      final tokenStorage = InMemorySecureTokenStorage();
      await tokenStorage.writeSession(
        ownerId: 'owner_err_test',
        tokens: AuthTokens(
          accessToken: 'valid_token_123',
          refreshToken: 'refresh_123',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 'MODEL_UNAVAILABLE',
            'type': 'Failure',
            'message': "Model category 'fast' is currently unavailable.",
          }),
          503,
        );
      });

      final streamClient = ChatStreamClient(
        tokenStorage: tokenStorage,
        client: mockClient,
      );

      expect(
        () => streamClient
            .streamCompletion(
              ownerId: 'owner_err_test',
              category: 'fast',
              catalogRevision: 'rev-1',
              messages: [
                {'role': 'user', 'content': 'Test'},
              ],
            )
            .toList(),
        throwsA(
          isA<CraftAiServerException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
    });
  });

  group('F07-01 & S10 Presentation UI Flow', () {
    testWidgets('error actions wrap on a narrow phone screen', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = InMemoryChatRepository();
      final conversation = await repo.createConversation(
        ownerId: 'narrow_owner',
      );
      await repo.saveMessage(
        ChatMessage(
          id: 'failed_reply',
          conversationId: conversation.id,
          ownerId: 'narrow_owner',
          role: MessageRole.assistant,
          content: '',
          status: MessageStatus.error,
          requestId: 'failed_request',
          errorMessage: 'Не удалось получить ответ от сервера.',
          createdAtUtc: DateTime.now().toUtc(),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            policyRepositoryProvider.overrideWithValue(MockPolicyRepository()),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AssistantChatPage(ownerId: 'narrow_owner'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final retry = find.byKey(const Key('chat.retryBtn'));
      final trace = find.byKey(const Key('chat.errorTraceBtn_failed_reply'));
      expect(retry, findsOneWidget);
      expect(trace, findsOneWidget);
      expect(
        tester.getTopLeft(trace).dy,
        greaterThan(tester.getTopLeft(retry).dy),
      );
    });

    testWidgets(
      'renders S10 header, empty state starter prompts, and sends message',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final chatRepo = InMemoryChatRepository();
        final tokenStorage = InMemorySecureTokenStorage();
        await tokenStorage.writeSession(
          ownerId: 'user_s10_1',
          tokens: AuthTokens(
            accessToken: 'token_abc',
            refreshToken: 'refresh_abc',
            expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        );

        final sseResponse =
            'event: text_delta\nid: 1\ndata: {"type":"text_delta","requestId":"r1","sequence":1,"eventId":"1","text":"Сила тока прямо пропорциональна напряжению."}\n\n'
            'event: terminal\nid: 2\ndata: {"type":"terminal","requestId":"r1","sequence":2,"eventId":"2","state":"completed"}\n\n';

        final mockHttpClient = MockClient((req) async {
          return http.Response.bytes(
            utf8.encode(sseResponse),
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        });

        final streamClient = ChatStreamClient(
          tokenStorage: tokenStorage,
          client: mockHttpClient,
        );

        final policyRepo = MockPolicyRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatRepositoryProvider.overrideWithValue(chatRepo),
              chatStreamClientProvider.overrideWithValue(streamClient),
              policyRepositoryProvider.overrideWithValue(policyRepo),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AssistantChatPage(ownerId: 'user_s10_1'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check S10 empty state elements
        expect(
          find.text('Чем помочь на уроке или в подготовке?'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('chat.promptOhm')), findsOneWidget);
        expect(find.byKey(const Key('chat.promptLesson')), findsOneWidget);
        expect(find.byKey(const Key('chat.promptMath')), findsOneWidget);

        // Check composer
        expect(find.byKey(const Key('chat.inputField')), findsOneWidget);
        expect(find.byKey(const Key('chat.sendBtn')), findsOneWidget);

        // Tap prompt card -> D02 consent sheet pops up!
        await tester.tap(find.byKey(const Key('chat.promptOhm')));
        await tester.pumpAndSettle();

        // Consent sheet D02 should be presented
        expect(find.text('Запросы уходят за рубеж'), findsOneWidget);

        // Tap "Понятно" (agree)
        await tester.tap(find.byKey(const Key('d02.understand')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();

        // Message should be sent and response rendered
        expect(find.textContaining('Объясни закон Ома'), findsOneWidget);
        expect(
          find.textContaining('Сила тока прямо пропорциональна напряжению'),
          findsOneWidget,
        );

        // Check message actions
        expect(find.byKey(const Key('chat.copyBtn')), findsOneWidget);
        expect(find.byKey(const Key('chat.reportBtn')), findsNothing);
        expect(find.byIcon(Icons.note_add_outlined), findsNothing);
        expect(find.byTooltip('Под капотом'), findsOneWidget);

        String? copiedText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.tap(find.byKey(const Key('chat.copyBtn')));
        await tester.pumpAndSettle();
        expect(copiedText, 'Сила тока прямо пропорциональна напряжению.');
        expect(find.text('Ответ скопирован'), findsOneWidget);

        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              throw PlatformException(code: 'clipboard_unavailable');
            }
            return null;
          },
        );
        await tester.tap(find.byKey(const Key('chat.copyBtn')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(
          find.text('Не удалось скопировать ответ. Попробуйте ещё раз.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('allows opening conversation history sheet', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chatRepo = InMemoryChatRepository();
      await chatRepo.createConversation(
        ownerId: 'user_hist_1',
        title: 'Разговор 1',
      );
      await chatRepo.createConversation(
        ownerId: 'user_hist_1',
        title: 'Разговор 2',
      );

      final tokenStorage = InMemorySecureTokenStorage();
      final streamClient = ChatStreamClient(tokenStorage: tokenStorage);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(chatRepo),
            chatStreamClientProvider.overrideWithValue(streamClient),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AssistantPage(ownerId: 'user_hist_1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap history icon in app bar
      await tester.tap(find.byKey(const Key('assistant.historyBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Verify sheet open
      expect(find.text('История разговоров'), findsOneWidget);
      expect(find.text('Разговор 1'), findsAtLeastNWidgets(1));
      expect(find.text('Разговор 2'), findsAtLeastNWidgets(1));
      expect(find.text('Режим без сохранения истории'), findsOneWidget);
    });
  });
}
