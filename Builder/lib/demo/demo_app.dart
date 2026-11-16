import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/localization/app_localizations.dart';
import '../app/providers.dart';
import '../features/agents/agents_providers.dart';
import '../features/agents/domain/lab_agent.dart';
import '../features/agents/infrastructure/agents_cache.dart';
import '../features/agents/infrastructure/agents_repository.dart';
import '../features/agents/infrastructure/lab_api_client.dart';
import '../features/agents/presentation/agents_page.dart';
import '../features/lab_runtime/domain/lab_run_models.dart' show LabModelInfo;
import '../features/lab_runtime/infrastructure/lab_runtime_api.dart';
import '../features/lab_runtime/presentation/lab_agent_chat_page.dart';
import '../features/lab_runtime/presentation/lab_agent_settings_page.dart';
import '../features/lab_runtime/presentation/lab_run_controller.dart';
import '../features/session/domain/auth_tokens.dart';
import '../features/session/infrastructure/secure_token_storage.dart';
import '../features/session/session_repository.dart';
import '../ui_kit/ui_kit.dart';
import 'demo_http_client.dart';

class DemoEnvironment {
  DemoEnvironment._(this.client, this.agents, this.runtime);
  final DemoHttpClient client;
  final AgentsRepository agents;
  final HttpLabRuntimeApi runtime;

  static Future<DemoEnvironment> create() async {
    final client = DemoHttpClient();
    final tokens = InMemorySecureTokenStorage();
    await tokens.writeSession(
      ownerId: DemoHttpClient.ownerId,
      tokens: AuthTokens(
        accessToken: 'demo-local-token',
        refreshToken: 'demo-local-refresh',
        expiresAtUtc: DateTime.utc(2100),
      ),
    );
    final uri = Uri.parse('https://demo.invalid');
    return DemoEnvironment._(
      client,
      AgentsRepository(
        api: LabApiClient(
          baseUri: uri,
          client: client,
          tokens: tokens,
          ownerId: DemoHttpClient.ownerId,
        ),
        cache: MemoryAgentsCache(),
      ),
      HttpLabRuntimeApi(
        client: client,
        baseUri: uri,
        getAccessToken: () async => 'demo-local-token',
      ),
    );
  }
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, required this.environment});
  final DemoEnvironment environment;
  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  static const owner = DemoHttpClient.ownerId;
  late final GoRouter _router = GoRouter(
    initialLocation: '/agents',
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/agents'),
      GoRoute(
        path: '/agents',
        builder: (_, _) => const AgentsPage(ownerId: owner),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, _) => const AgentEditorPage(ownerId: owner),
          ),
          GoRoute(
            path: ':agentId',
            builder: (_, state) =>
                _DemoAgentPage(agentId: state.pathParameters['agentId']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) => AgentEditorPage(
                  ownerId: owner,
                  agentId: state.pathParameters['agentId']!,
                ),
              ),
              GoRoute(
                path: 'chat',
                builder: (_, state) => _DemoRuntimePage(
                  agentId: state.pathParameters['agentId']!,
                  environment: widget.environment,
                  settings: false,
                ),
              ),
              GoRoute(
                path: 'settings',
                builder: (_, state) => _DemoRuntimePage(
                  agentId: state.pathParameters['agentId']!,
                  environment: widget.environment,
                  settings: true,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    widget.environment.client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      sessionProvider.overrideWith(
        (ref) => Stream.value(
          AuthenticatedSession(ownerId: owner, onboardingComplete: true),
        ),
      ),
      agentsRepositoryProvider(
        owner,
      ).overrideWithValue(widget.environment.agents),
    ],
    child: _DemoMaterialApp(router: _router),
  );
}

class _DemoMaterialApp extends ConsumerWidget {
  const _DemoMaterialApp({required this.router});
  final GoRouter router;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: BuilderTheme.light,
    locale: ref.watch(appLocaleProvider) ?? const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => Column(
      children: [
        Material(
          color: BuilderColors.warningTint,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(AppLocalizations.of(context).demoBanner),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child!),
      ],
    ),
  );
}

class _DemoAgentPage extends ConsumerWidget {
  const _DemoAgentPage({required this.agentId});
  final String agentId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    return _agentView(
      ref,
      agentId,
      (agent) => Scaffold(
        appBar: AppBar(title: Text(agent.name)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(s.demoWelcome, style: BuilderType.h2),
            const SizedBox(height: 12),
            Text(s.demoGuide),
            const SizedBox(height: 20),
            BuilderCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${agent.subject} · ${agent.grade}',
                    style: BuilderType.h2,
                  ),
                  const SizedBox(height: 8),
                  Text(agent.instruction),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push('/agents/$agentId/chat'),
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(s.demoChat),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/agents/$agentId/settings'),
              icon: const Icon(Icons.tune),
              label: Text(s.demoResources),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.push('/agents/$agentId/edit'),
              child: Text(s.agentsInstruction),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _agentView(
  WidgetRef ref,
  String id,
  Widget Function(LabAgent) builder,
) => ref
    .watch(agentsProvider(DemoHttpClient.ownerId))
    .when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) =>
          const Scaffold(body: Center(child: Text('Демо: обновите страницу.'))),
      data: (snapshot) {
        final agent = snapshot.agents
            .where((item) => item.id == id)
            .firstOrNull;
        return agent == null
            ? const Scaffold(
                body: Center(child: Text('Агент удалён. Вернитесь в список.')),
              )
            : builder(agent);
      },
    );

class _DemoRuntimePage extends ConsumerWidget {
  const _DemoRuntimePage({
    required this.agentId,
    required this.environment,
    required this.settings,
  });
  final String agentId;
  final DemoEnvironment environment;
  final bool settings;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _agentView(ref, agentId, (agent) {
        final permissions = agent.json['permissions'] as Map;
        final models = DemoHttpClient.models
            .map((id) => LabModelInfo(modelId: id, supportsTools: true))
            .toList();
        final model = models.firstWhere(
          (model) => model.modelId == agent.json['model_id'],
          orElse: () => models.first,
        );
        if (settings) {
          return LabAgentSettingsPage(
            agentId: agentId,
            api: environment.runtime,
            availableModels: models,
            initialModelId: model.modelId,
            initialInstruction: agent.instruction,
            initialAllowSave: permissions['save_material'] == true,
            initialAllowSearch: permissions['search_materials'] == true,
            onSaveCoreSettings:
                ({
                  required modelId,
                  required instruction,
                  required allowSave,
                  required allowSearch,
                }) async {
                  try {
                    await ref
                        .read(agentsProvider(DemoHttpClient.ownerId).notifier)
                        .mutate(
                          (repo) => repo.update(agentId, {
                            'model_id': modelId,
                            'instruction': instruction,
                            'permissions': {
                              'save_material': allowSave,
                              'search_materials': allowSearch,
                            },
                          }),
                        );
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            agentError(AppLocalizations.of(context), error),
                          ),
                        ),
                      );
                    }
                  }
                },
          );
        }
        return _DemoChat(agent: agent, environment: environment, model: model);
      });
}

class _DemoChat extends StatefulWidget {
  const _DemoChat({
    required this.agent,
    required this.environment,
    required this.model,
  });
  final LabAgent agent;
  final DemoEnvironment environment;
  final LabModelInfo model;
  @override
  State<_DemoChat> createState() => _DemoChatState();
}

class _DemoChatState extends State<_DemoChat> {
  late final controller = LabRunController(
    api: widget.environment.runtime,
    config: LabAgentRunConfig(
      agentId: widget.agent.id,
      model: widget.model,
      allowSave:
          (widget.agent.json['permissions'] as Map)['save_material'] == true,
      allowSearch:
          (widget.agent.json['permissions'] as Map)['search_materials'] == true,
    ),
  );
  @override
  Widget build(BuildContext context) => LabAgentChatPage(
    agentName: widget.agent.name,
    controller: controller,
    onOpenSettings: () => context.go('/agents/${widget.agent.id}/settings'),
  );
}
