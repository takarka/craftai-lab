import 'dart:io';
import 'package:http/io_client.dart';
import 'package:builder/features/auth/infrastructure/craft_ai_auth_gateway.dart';
import 'package:builder/features/models/domain/model_catalog.dart';
import 'package:builder/features/models/domain/model_category.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/session/infrastructure/refreshing_token_storage.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const backendBaseUrl = 'https://localhost:5001';
  final baseUri = Uri.parse(backendBaseUrl);

  final io = HttpClient()..badCertificateCallback = (cert, host, port) => true;
  final httpClient = IOClient(io);

  group('F20 Live Backend End-to-End Integration Tests', () {
    test('1. Fetch legal documents in RU and KK', () async {
      final gateway = CraftAiAuthGateway(
        baseUri: baseUri,
        httpClient: httpClient,
      );
      await gateway.fetchDocuments('ru');
      await gateway.fetchDocuments('kk');

      final ruDocs = gateway.documentsFor('ru');
      expect(ruDocs, isNotNull);
      expect(ruDocs!.terms.revision, isNotEmpty);
      expect(ruDocs.privacy.revision, isNotEmpty);
      expect(ruDocs.terms.body, contains('CraftAI'));

      final kkDocs = gateway.documentsFor('kk');
      expect(kkDocs, isNotNull);
      expect(kkDocs!.terms.revision, isNotEmpty);
      expect(kkDocs.privacy.revision, isNotEmpty);
      expect(kkDocs.terms.body, contains('CraftAI'));
    });

    test(
      '2. Superadmin login, token storage, and session establishment',
      () async {
        final inMemoryStorage = InMemorySecureTokenStorage();
        final gateway = CraftAiAuthGateway(
          baseUri: baseUri,
          httpClient: httpClient,
          tokenStorage: inMemoryStorage,
        );

        await gateway.signIn(
          email: 'local-dev@craft-ai.local',
          password: 'LocalDevPass123!',
        );

        final tokens = await inMemoryStorage.readTokens();
        expect(tokens, isNotNull);
        expect(tokens!.accessToken, isNotEmpty);
        expect(tokens.refreshToken, isNotEmpty);
        expect(tokens.isExpired, isFalse);

        final ownerId = await inMemoryStorage.readOwnerId();
        expect(ownerId, isNotNull);
        expect(ownerId, isNotEmpty);
      },
    );

    test('3. Token refresh via RefreshingTokenStorage', () async {
      final inMemoryStorage = InMemorySecureTokenStorage();
      final gateway = CraftAiAuthGateway(
        baseUri: baseUri,
        httpClient: httpClient,
        tokenStorage: inMemoryStorage,
      );

      await gateway.signIn(
        email: 'local-dev@craft-ai.local',
        password: 'LocalDevPass123!',
      );

      final refreshingStorage = RefreshingTokenStorage(
        storage: inMemoryStorage,
        baseUri: baseUri,
        client: httpClient,
      );

      final initialTokens = await inMemoryStorage.readTokens();
      expect(initialTokens, isNotNull);

      final refreshedTokens = await refreshingStorage.refreshTokens();
      expect(refreshedTokens, isNotNull);
      expect(refreshedTokens!.accessToken, isNotEmpty);
      expect(refreshedTokens.refreshToken, isNotEmpty);
    });

    test(
      '4. Fetch model catalog via CraftAiClient with authenticated session',
      () async {
        final inMemoryStorage = InMemorySecureTokenStorage();
        final gateway = CraftAiAuthGateway(
          baseUri: baseUri,
          httpClient: httpClient,
          tokenStorage: inMemoryStorage,
        );

        await gateway.signIn(
          email: 'local-dev@craft-ai.local',
          password: 'LocalDevPass123!',
        );

        final client = CraftAiClient(
          baseUri: baseUri,
          httpClient: httpClient,
          tokenStorage: inMemoryStorage,
        );

        final json = await client.getJson('/builder/models');
        expect(json, isNotNull);
        final catalog = ModelCatalog.fromJson(json);

        expect(catalog.revision, isNotEmpty);
        expect(catalog.models, isNotEmpty);

        final fast = catalog.getModel(ModelCategory.fast);
        expect(fast, isNotNull);
        expect(fast.modelId, contains('gemini'));

        final standard = catalog.getModel(ModelCategory.standard);
        expect(standard, isNotNull);
        expect(standard.modelId, contains('qwen'));

        final advanced = catalog.getModel(ModelCategory.advanced);
        expect(advanced, isNotNull);
        expect(advanced.modelId, contains('deepseek'));
      },
    );

    test(
      '5. Register new user with legal document revisions and verify session',
      () async {
        final gateway = CraftAiAuthGateway(
          baseUri: baseUri,
          httpClient: httpClient,
        );
        await gateway.fetchDocuments('ru');
        final docs = gateway.documentsFor('ru')!;

        final uniqueEmail =
            'pilot.user.${DateTime.now().millisecondsSinceEpoch}@craft-ai.local';
        final inMemoryStorage = InMemorySecureTokenStorage();
        final userGateway = CraftAiAuthGateway(
          baseUri: baseUri,
          httpClient: httpClient,
          tokenStorage: inMemoryStorage,
        );

        await userGateway.register(
          name: 'Данияр Сатпаев',
          email: uniqueEmail,
          password: 'PilotStrongPass2026!',
          termsRevision: docs.terms.revision,
          privacyRevision: docs.privacy.revision,
        );

        final tokens = await inMemoryStorage.readTokens();
        expect(tokens, isNotNull);
        expect(tokens!.accessToken, isNotEmpty);
        expect(tokens.refreshToken, isNotEmpty);

        final ownerId = await inMemoryStorage.readOwnerId();
        expect(ownerId, isNotNull);
        expect(ownerId, isNotEmpty);
      },
    );
  });
}
