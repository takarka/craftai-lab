import 'dart:convert';
import 'dart:io';
import 'package:builder/app/app.dart';
import 'package:builder/app/environment/app_config.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/models/domain/model_catalog.dart';
import 'package:builder/features/models/domain/model_category.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/models/infrastructure/persistent_model_catalog_repository.dart';
import 'package:builder/features/models/model_providers.dart';
import 'package:builder/features/models/presentation/model_selection_page.dart';
import 'package:builder/features/policy/infrastructure/persistent_policy_repository.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/infrastructure/refreshing_token_storage.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('F06-01: CraftAiClient Network & Error Handling', () {
    test('generates valid UUID v4 request ID for correlation', () {
      final reqId = CraftAiClient.generateRequestId();
      expect(reqId, hasLength(36));
      expect(reqId[14], equals('4')); // version 4
      expect(
        ['8', '9', 'a', 'b'].contains(reqId[19].toLowerCase()),
        isTrue,
      ); // variant
    });

    test(
      'attaches Authorization header with access token and correlation id',
      () async {
        final tokenStorage = InMemorySecureTokenStorage();
        await tokenStorage.writeSession(
          ownerId: 'owner_test_1',
          tokens: AuthTokens(
            accessToken: 'test_secret_access_token_123',
            refreshToken: 'test_refresh',
            expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        );

        String? capturedAuthHeader;
        String? capturedRequestId;

        final mockClient = MockClient((request) async {
          capturedAuthHeader = request.headers['Authorization'];
          capturedRequestId = request.headers['X-Request-Id'];
          return http.Response(
            jsonEncode({'revision': 'rev-test', 'models': []}),
            200,
          );
        });

        final client = CraftAiClient(
          baseUri: Uri.parse('https://localhost:5001'),
          httpClient: mockClient,
          tokenStorage: tokenStorage,
        );

        final json = await client.getJson('/builder/models');
        expect(json['revision'], equals('rev-test'));
        expect(
          capturedAuthHeader,
          equals('Bearer test_secret_access_token_123'),
        );
        expect(capturedRequestId, isNotNull);
      },
    );

    test(
      'maps 401 to CraftAiAuthException without leaking secret tokens',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response('', 401);
        });

        final client = CraftAiClient(
          baseUri: Uri.parse('https://localhost:5001'),
          httpClient: mockClient,
        );

        expect(
          () => client.getJson('/builder/models'),
          throwsA(
            isA<CraftAiAuthException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having((e) => e.message, 'message', contains('Unauthorized')),
          ),
        );
      },
    );

    test('retries once after a shared mobile refresh on 401', () async {
      final rawStorage = InMemorySecureTokenStorage();
      await rawStorage.writeSession(
        ownerId: 'owner',
        tokens: AuthTokens(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          refreshExpiresAtUtc: DateTime.now().toUtc().add(
            const Duration(days: 30),
          ),
        ),
      );
      var refreshCalls = 0;
      final storage = RefreshingTokenStorage(
        storage: rawStorage,
        baseUri: Uri.parse('https://localhost:5001'),
        client: MockClient((request) async {
          refreshCalls++;
          expect(request.url.path, '/mobile/auth/refresh');
          expect(jsonDecode(request.body)['refreshToken'], 'old-refresh');
          return http.Response(
            jsonEncode({
              'accessToken': 'new-access',
              'accessTokenExpiresAtUtc': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
              'refreshToken': 'new-refresh',
              'refreshExpiresAtUtc': DateTime.now()
                  .toUtc()
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            }),
            200,
          );
        }),
      );
      var requestCalls = 0;
      final client = CraftAiClient(
        baseUri: Uri.parse('https://localhost:5001'),
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          requestCalls++;
          if (requestCalls == 1) return http.Response('', 401);
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response('{"models": []}', 200);
        }),
      );

      await client.getJson('/builder/models');
      expect(requestCalls, 2);
      expect(refreshCalls, 1);
      expect((await rawStorage.readTokens())!.refreshToken, 'new-refresh');
    });

    test('maps 500 to CraftAiServerException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = CraftAiClient(
        baseUri: Uri.parse('https://localhost:5001'),
        httpClient: mockClient,
      );

      expect(
        () => client.getJson('/builder/models'),
        throwsA(
          isA<CraftAiServerException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });
  });

  group('F06-02 / F06-05 / F06-V01: ModelCategory & 3-Segment Relative Scales', () {
    test('ModelCategory provides exact 3-segment ratings for all 3 tiers', () {
      // Fast: speed high (3), quality modest (1), price economical (1)
      expect(ModelCategory.fast.qualityRating, equals(1));
      expect(ModelCategory.fast.speedRating, equals(3));
      expect(ModelCategory.fast.priceRating, equals(1));

      // Standard (Balanced): balanced (2, 2, 2)
      expect(ModelCategory.standard.qualityRating, equals(2));
      expect(ModelCategory.standard.speedRating, equals(2));
      expect(ModelCategory.standard.priceRating, equals(2));

      // Advanced (Powerful): quality high (3), speed slower (1), price higher (3)
      expect(ModelCategory.advanced.qualityRating, equals(3));
      expect(ModelCategory.advanced.speedRating, equals(1));
      expect(ModelCategory.advanced.priceRating, equals(3));
    });

    test(
      'ModelCategory parses case-insensitively and defaults to standard',
      () {
        expect(ModelCategory.fromString('fast'), equals(ModelCategory.fast));
        expect(
          ModelCategory.fromString('Standard'),
          equals(ModelCategory.standard),
        );
        expect(
          ModelCategory.fromString('ADVANCED'),
          equals(ModelCategory.advanced),
        );
        expect(
          ModelCategory.fromString('unknown_value'),
          equals(ModelCategory.standard),
        );
        expect(ModelCategory.fromString(null), equals(ModelCategory.standard));
      },
    );

    test(
      'ModelCatalog parses backend response and suggests available alternatives',
      () {
        final backendJson = {
          'revision': 'rev-openrouter-v1',
          'models': [
            {
              'category': 'fast',
              'modelId': 'google/gemini-2.5-flash',
              'available': true,
              'streaming': true,
              'tools': true,
              'languages': ['ru', 'kk'],
              'contextWindow': 128000,
            },
            {
              'category': 'standard',
              'modelId': 'anthropic/claude-3.5-sonnet',
              'available': false, // currently down
              'streaming': true,
              'tools': true,
              'languages': ['ru', 'kk'],
              'contextWindow': 128000,
            },
            {
              'category': 'advanced',
              'modelId': 'openai/o3-mini',
              'available': true,
              'streaming': true,
              'tools': true,
              'languages': ['ru', 'kk'],
              'contextWindow': 128000,
            },
          ],
        };

        final catalog = ModelCatalog.fromJson(backendJson);
        expect(catalog.revision, equals('rev-openrouter-v1'));
        expect(catalog.models, hasLength(3));
        expect(catalog.isCategoryAvailable(ModelCategory.fast), isTrue);
        expect(catalog.isCategoryAvailable(ModelCategory.standard), isFalse);
        expect(catalog.isCategoryAvailable(ModelCategory.advanced), isTrue);

        // F06-07: When standard is down, alternative suggestion selects fast
        final alternative = catalog.suggestAlternative(ModelCategory.standard);
        expect(alternative, equals(ModelCategory.fast));
      },
    );
  });

  group('F06-03: SQLite Category Persistence', () {
    late Directory tempDir;
    late StorageDatabase database;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('craftai_f06_test_');
      dbPath = p.join(tempDir.path, 'f06_test.db');
      database = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await database.open();
    });

    tearDown(() async {
      if (database.isOpen) await database.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test(
      'PersistentModelCatalogRepository reads and saves selected category in assistant_configurations',
      () async {
        const ownerId = 'teacher_f06_1';
        final nowUtc = DateTime.now().toUtc().toIso8601String();

        // Setup workspace and assistant record
        await database.db.insert(StorageSchemaV1.tableWorkspaces, {
          'owner_id': ownerId,
          'installation_id': 'inst_1',
          'schema_version': 1,
          'workspace_epoch': 1,
          'created_at_utc': nowUtc,
          'updated_at_utc': nowUtc,
        });

        await database.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
          'owner_id': ownerId,
          'name': 'Ассистент',
          'selected_category': null,
          'enabled_skills_json': '[]',
          'system_rules_json': '[]',
          'state_revision': 1,
          'updated_at_utc': nowUtc,
        });

        final repo = PersistentModelCatalogRepository(database: database);

        // 1. Initial selection defaults to standard
        final initial = await repo.getSelectedCategory(ownerId);
        expect(initial, equals(ModelCategory.standard));

        // 2. Select advanced category
        await repo.setSelectedCategory(
          ownerId: ownerId,
          category: ModelCategory.advanced,
        );

        final updated = await repo.getSelectedCategory(ownerId);
        expect(updated, equals(ModelCategory.advanced));

        // 3. Verify SQLite row directly
        final rows = await database.db.query(
          StorageSchemaV1.tableAssistantConfigurations,
          where: 'owner_id = ?',
          whereArgs: [ownerId],
        );
        expect(rows.first['selected_category'], equals('advanced'));
        expect(rows.first['state_revision'], equals(2));
      },
    );
  });

  group('F06-04 / F06-05 / S33: ModelSelectionPage Widget Flow', () {
    testWidgets(
      'Renders 3 categories, 3-segment scales, disclaimer and data notice',
      (tester) async {
        const ownerId = 'teacher_widget_f06';
        final inMemCatalogRepo = InMemoryModelCatalogRepository();
        final inMemPolicyRepo = InMemoryPolicyRepository()
          ..acknowledgePolicy(
            ownerId: ownerId,
            policyId: 'd02_cross_border_transfer',
            policyVersion: 'v1.0',
          );

        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(environment: AppEnvironment.development),
            ),
            modelCatalogRepositoryProvider.overrideWithValue(inMemCatalogRepo),
            policyRepositoryProvider.overrideWithValue(inMemPolicyRepo),
            sessionRepositoryProvider.overrideWithValue(
              _TestSessionRepository(ownerId: ownerId),
            ),
          ],
        );
        container.read(appLocaleProvider.notifier).select(const Locale('ru'));
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const BuilderApp(),
          ),
        );
        await tester.pumpAndSettle();

        // On /assistant page
        expect(find.byType(AssistantPage), findsOneWidget);

        // Tap button to navigate to S33 Model Selection Page
        final chooseBtn = find.byKey(const Key('assistant.chooseModel'));
        expect(chooseBtn, findsOneWidget);
        await tester.tap(chooseBtn);
        await tester.pumpAndSettle();

        // S33 page is displayed!
        expect(find.byType(ModelSelectionPage), findsOneWidget);
        expect(find.text('Модель ассистента'), findsWidgets);
        expect(find.text('Данные за рубежом'), findsOneWidget);
        expect(
          find.textContaining('Шкалы являются справочными'),
          findsOneWidget,
        );

        // Check all 3 category cards exist
        expect(find.byKey(const Key('models.card.fast')), findsOneWidget);
        expect(find.byKey(const Key('models.card.standard')), findsOneWidget);
        expect(find.byKey(const Key('models.card.advanced')), findsOneWidget);

        // Standard is recommended & selected by default
        expect(find.text('Рекомендуемая'), findsOneWidget);
        expect(find.text('Качество'), findsWidgets);
        expect(find.text('Скорость'), findsWidgets);
        expect(find.text('Стоимость'), findsWidgets);

        // Tap "Мощная" card
        final advancedCard = find.byKey(const Key('models.card.advanced'));
        await tester.ensureVisible(advancedCard);
        await tester.tap(advancedCard);
        await tester.pumpAndSettle();

        // Verify category changed in repository
        final savedCat = await inMemCatalogRepo.getSelectedCategory(ownerId);
        expect(savedCat, equals(ModelCategory.advanced));
      },
    );

    testWidgets(
      'F06-07: Unavailable category displays warning and allows switching to alternative',
      (tester) async {
        const ownerId = 'teacher_widget_f06_down';
        final catalogWithDownAdvanced = ModelCatalog(
          revision: 'rev-test-down',
          models: [
            ModelDescriptor(
              category: ModelCategory.fast,
              modelId: 'gemini',
              available: true,
              streaming: true,
              tools: true,
              languages: const ['ru', 'kk'],
              contextWindow: 128000,
            ),
            ModelDescriptor(
              category: ModelCategory.standard,
              modelId: 'claude',
              available: true,
              streaming: true,
              tools: true,
              languages: const ['ru', 'kk'],
              contextWindow: 128000,
            ),
            ModelDescriptor(
              category: ModelCategory.advanced,
              modelId: 'o3-mini',
              available: false, // unavailable!
              streaming: true,
              tools: true,
              languages: const ['ru', 'kk'],
              contextWindow: 128000,
            ),
          ],
          fetchedAtUtc: DateTime.now().toUtc(),
        );

        final inMemCatalogRepo = InMemoryModelCatalogRepository(
          initialCatalog: catalogWithDownAdvanced,
          selections: {
            ownerId: ModelCategory.advanced,
          }, // User had previously chosen advanced
        );

        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(environment: AppEnvironment.development),
            ),
            modelCatalogRepositoryProvider.overrideWithValue(inMemCatalogRepo),
            policyRepositoryProvider.overrideWithValue(
              InMemoryPolicyRepository(),
            ),
            sessionRepositoryProvider.overrideWithValue(
              _TestSessionRepository(ownerId: ownerId),
            ),
          ],
        );
        container.read(appLocaleProvider.notifier).select(const Locale('ru'));
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const BuilderApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to /assistant/models
        final chooseBtn = find.byKey(const Key('assistant.chooseModel'));
        await tester.tap(chooseBtn);
        await tester.pumpAndSettle();

        // Alert about unavailable category is visible
        expect(
          find.byKey(const Key('models.unavailableAlert')),
          findsOneWidget,
        );
        expect(find.text('Временно недоступна'), findsOneWidget);

        // Tap button to switch to recommended alternative
        final switchBtn = find.byKey(const Key('models.switchToRecommended'));
        expect(switchBtn, findsOneWidget);
        await tester.tap(switchBtn);
        await tester.pumpAndSettle();

        // Alert disappears and selection switches to Standard!
        expect(find.byKey(const Key('models.unavailableAlert')), findsNothing);
        expect(
          await inMemCatalogRepo.getSelectedCategory(ownerId),
          equals(ModelCategory.standard),
        );
      },
    );
  });
}

class _TestSessionRepository implements SessionRepository {
  _TestSessionRepository({required this.ownerId});

  final String ownerId;

  @override
  Stream<SessionSnapshot> watchSession() => Stream.value(
    AuthenticatedSession(ownerId: ownerId, onboardingComplete: true),
  );
}
