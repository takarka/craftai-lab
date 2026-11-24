import 'dart:async';
import 'dart:convert';

import 'package:builder/app/app.dart';
import 'package:builder/app/environment/app_config.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/core/errors/app_failure.dart';
import 'package:builder/features/agents/agents_providers.dart';
import 'package:builder/features/agents/domain/lab_agent.dart';
import 'package:builder/features/agents/infrastructure/agents_cache.dart';
import 'package:builder/features/agents/infrastructure/agents_repository.dart';
import 'package:builder/features/agents/infrastructure/lab_api_client.dart';
import 'package:builder/features/auth/application/auth_controller.dart';
import 'package:builder/features/auth/domain/auth_gateway.dart';
import 'package:builder/features/auth/infrastructure/auth_credentials_storage.dart';
import 'package:builder/features/course/course_providers.dart';
import 'package:builder/features/course/domain/transfer_review.dart';
import 'package:builder/features/course/infrastructure/in_memory_course_repository.dart';
import 'package:builder/features/course/infrastructure/transfer_review_store.dart';
import 'package:builder/features/lab_runtime/infrastructure/lab_runtime_api.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_workspace_page.dart';
import 'package:builder/features/onboarding/application/onboarding_controller.dart';
import 'package:builder/features/onboarding/domain/assistant_setup.dart';
import 'package:builder/features/onboarding/domain/initial_workspace_repository.dart';
import 'package:builder/features/profile/domain/profile.dart';
import 'package:builder/features/profile/profile_providers.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const owner = 'guide-fixture-owner';
const agentId = 'fractions-demo';
const model = 'google/gemini-2.5-flash';
const name = 'Помощник по дробям';
const instruction =
    'Готовь задания по дробям для 5 класса. Давай две короткие подсказки. Не называй решение без просьбы.';
const prompt =
    'Используй только карточку: при одинаковых знаменателях сравни числители. Дай ученику 5 класса две короткие подсказки, как сравнить 3/8 и 5/8. Не называй готовый ответ.';
final setup = AssistantSetup(
  subject: SchoolSubject.mathematics,
  grades: {5},
  language: AssistantLanguage.russian,
  name: name,
);

class FixtureSession implements SessionRepository {
  FixtureSession(this.value);
  SessionSnapshot value;
  final updates = StreamController<SessionSnapshot>.broadcast();
  void set(SessionSnapshot next) {
    value = next;
    updates.add(next);
  }

  @override
  Stream<SessionSnapshot> watchSession() async* {
    yield value;
    yield* updates.stream;
  }
}

class FixtureAuth implements AuthGateway {
  FixtureAuth(this.session);
  final FixtureSession session;
  @override
  bool get isAvailable => true;

  @override
  AuthLegalDocuments documentsFor(String languageCode) => const AuthLegalDocuments(
    terms: LegalDocument(body: 'Условия использования CraftAI Lab. Учебная демонстрация.', revision: 'guide-terms-1'),
    privacy: LegalDocument(body: 'Используйте только вымышленные данные. Политика конфиденциальности.', revision: 'guide-privacy-1'),
  );

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (password != 'demo-fractions-2026') {
      throw const AppFailure(AppFailureCode.invalidCredentials);
    }
    session.set(AuthenticatedSession(ownerId: owner, onboardingComplete: true));
  }

  @override
  Future<void> register({
    required String name, required String email, required String password,
    required String termsRevision, required String privacyRevision,
  }) async {
    if (password.length < 8) throw const AppFailure(AppFailureCode.weakPassword);
    session.set(AuthenticatedSession(ownerId: owner, onboardingComplete: false));
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {}
  @override
  Future<void> resetPassword({required String token, required String newPassword}) async {}
  @override
  Future<void> changePassword({required String newPassword}) async {}
  @override
  Future<void> logout() async => session.set(const SignedOut());
}

class FixtureWorkspace implements InitialWorkspaceRepository {
  @override
  bool get isAvailable => true;
  @override
  Future<InitialWorkspace> createIfAbsent({
    required WorkspaceWritePermit permit,
    required AssistantSetup setup,
  }) async => InitialWorkspace(ownerId: permit.ownerId, setup: setup);
}

class FixtureProfile implements ProfileAccountGateway {
  @override
  bool get isAvailable => true;
  @override
  Future<AccountSnapshot> load(String id) async => AccountSnapshot(
    ownerId: id, name: 'Айдана Садыкова', email: 'teacher@example.test',
    role: 'Педагог', usedTokens: 1280,
    periodStartUtc: DateTime.utc(2026, 11, 1),
    periodEndUtc: DateTime.utc(2026, 11, 30),
    updatedAtUtc: DateTime.utc(2026, 11, 24),
  );
  @override
  Future<void> deleteAccount(String ownerId) async {}
}

class FixtureAgents extends AgentsRepository {
  FixtureAgents(http.Client client)
      : super(
          api: LabApiClient(
            baseUri: Uri.parse('https://fixture.invalid'), client: client,
            tokens: InMemorySecureTokenStorage(), ownerId: owner,
          ), cache: MemoryAgentsCache(),
        );

  final List<LabAgent> agents = [
    LabAgent({
      'id': agentId, 'name': name, 'subject': 'Математика', 'grade': '5',
      'task_type': 'prepare_tasks', 'version': 2, 'instruction': instruction,
      'model_id': model,
      'permissions': {'save_material': true, 'search_materials': true},
    }),
    LabAgent({
      'id': 'review-demo', 'name': 'Проверка объяснений', 'subject': 'Математика', 'grade': '5',
      'version': 1, 'instruction': 'Проверяй ответ только по учебной карточке.',
      'model_id': model,
    }),
  ];

  @override
  Future<AgentsSnapshot> load() async => AgentsSnapshot(List.of(agents));

  @override
  Future<LabAgent> create(Map<String, dynamic> config) async {
    final agent = LabAgent({...config, 'id': 'local-demo', 'version': 1});
    agents.add(agent);
    return agent;
  }
}

Map<String, dynamic> run(String id, String answer, {
  String status = 'completed',
  List<Map<String, dynamic>> events = const [],
  List<Map<String, dynamic>> actions = const [],
}) => {
  'id': id, 'agent_id': agentId, 'status': status, 'model_id': model,
  'agent_version_id': '2', 'epoch': 1, 'final_output': answer,
  'active_elapsed_ms': 830, 'tool_calls_count': events.isEmpty ? 0 : 1,
  'events': events, 'pending_actions': actions,
};

http.Response response(Object value) =>
    http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json; charset=utf-8'});

const routes = <String, String>{
  '01-sign-in': '/sign-in', '02-register': '/register',
  '03-password-mismatch': '/register', '04-recover': '/recover-password',
  '05-welcome': '/onboarding', '06-preferences': '/onboarding/preferences',
  '07-name-assistant': '/onboarding/assistant', '08-agents': '/agents',
  '09-agent-editor': '/agents/new', '10-dialogue': '/agents/$agentId/chat',
  '11-trace': '/agents/$agentId/runs/demo-run',
  '12-agent-settings': '/agents/$agentId/settings',
  '13-materials': '/agents/$agentId/settings',
  '24-memory-skills': '/agents/$agentId/settings',
  '25-approval': '/agents/$agentId/chat',
  '14-course': '/course', '27-course-bottom': '/course', '15-lesson': '/course/lesson/1',
  '28-preferences-language': '/onboarding/preferences', '30-agent-wizard': '/agents',
  '31-course-explanation': '/course/lesson/1', '32-course-summary': '/course/lesson/1',
  '23-lesson-practice': '/course/lesson/1',
  '26-course-quiz': '/course/lesson/1',
  '16-profile': '/profile', '17-app-settings': '/profile/settings',
  '18-privacy': '/profile/privacy', '19-help': '/profile/help',
  '20-capstone-prompt': '/course/lesson/12',
  '21-capstone-rubric': '/course/lesson/12', '22-capstone-result': '/course/lesson/12',
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scene = Uri.base.queryParameters['scene'] ?? '01-sign-in';
  final target = routes[scene] ?? '/sign-in';
  final course = InMemoryCourseRepository();
  if (scene == '14-course' || scene == '27-course-bottom' || scene.contains('capstone')) {
    for (final level in [1, 2, 10, 3, 4, 5]) {
      await course.completeLevel(ownerId: owner, levelId: level);
    }
  }
  final demoStep = {
    '23-lesson-practice': 2, '31-course-explanation': 3,
    '26-course-quiz': 4, '32-course-summary': 5,
  }[scene];
  if (demoStep != null) {
    await course.saveCheckpoint(ownerId: owner, levelId: 1, step: demoStep, practiceEvidenceMet: demoStep > 2);
  }
  if (scene.contains('capstone')) {
    final first = scene != '20-capstone-prompt';
    final repeat = scene == '22-capstone-result';
    await course.saveCheckpoint(ownerId: owner, levelId: 12, step: 2, practiceEvidenceMet: repeat);
    await const TransferReviewStore().write(owner, TransferReview(
      prompt: prompt,
      firstAnswer: first ? '3/8 меньше 5/8, потому что числитель 3 меньше 5.' : '',
      first: first ? {
        for (final key in TransferCriterion.values)
          key: key == TransferCriterion.format ? TransferVerdict.revise : TransferVerdict.met,
      } : const {},
      instructionChange: repeat ? 'Давай две отдельные подсказки без готового ответа.' : '',
      secondAnswer: repeat ? '1. Проверь знаменатели.\n2. Сравни числа над чертой.' : '',
      second: repeat ? {for (final key in TransferCriterion.values) key: TransferVerdict.met} : const {},
    ));
  }
  final session = FixtureSession(const SignedOut());
  final finished = run('demo-run', 'Правило найдено в учебном материале. Сравните числители при одинаковых знаменателях.', events: [
    {'sequence': 1, 'event_type': 'tool_completed', 'payload': {
      'tool_name': 'search_materials', 'params': {'query': 'Равные знаменатели'},
    }},
  ]);
  final client = MockClient((req) async {
    final path = req.url.path;
    if (path.endsWith('/models')) return response({'models': [{'model_id': model, 'available': true, 'supports_tools': true, 'supports_vision': true}]});
    if (path.endsWith('/dialogue')) return response({
      'conversation_id': 'guide-dialogue',
      'turns': [
        {'prompt': 'Дай две подсказки по сравнению 3/8 и 5/8 для 5 класса.', 'run': run('first-run', '1. Посмотри, равны ли знаменатели.\n2. Сравни числители.')},
        {'prompt': 'Сформулируй вторую подсказку короче.', 'run': run('second-run', 'Сравни числа над чертой.')},
        if (scene == '25-approval') {'prompt': 'Сохрани материал «Сравнение дробей».', 'run': run('approval-run', '', status: 'awaiting_confirmation', actions: [
          {'id':'guide-action','tool_name':'save_material','status':'pending','params':{'title':'Сравнение дробей','content':'При равных знаменателях сравни числители.'}},
        ])},
      ],
    });
    if (path.endsWith('/materials')) return response({'items': [{'id':'sample-frac','title':'Сравнение дробей','content':'При равных знаменателях сравни числители.'}]});
    if (path.endsWith('/memory')) return response({'items': [{'id':'memory-1','content':'Предлагать не больше двух подсказок.'}]});
    if (path.endsWith('/skills')) return response({'items': [{'slug':'lesson-hints','title':'Учебные подсказки','enabled':true,'base_content':'Две подсказки по шагам без готового ответа.','revision':1}]});
    if (path.contains('/runs/')) return response(finished);
    if (path.endsWith('/runs')) return response(run('fixture-new', 'Сравни числители при одинаковых знаменателях.'));
    return response({});
  });
  final api = HttpLabRuntimeApi(client: client, baseUri: Uri.parse('https://fixture.invalid'), getAccessToken: () async => null);
  final container = ProviderContainer(overrides: [
    appConfigProvider.overrideWithValue(const AppConfig(environment: AppEnvironment.development)),
    sessionRepositoryProvider.overrideWithValue(session),
    authGatewayProvider.overrideWithValue(FixtureAuth(session)),
    authCredentialsStorageProvider.overrideWithValue(InMemoryAuthCredentialsStorage()),
    initialWorkspaceRepositoryProvider.overrideWithValue(FixtureWorkspace()),
    agentsRepositoryProvider(owner).overrideWithValue(FixtureAgents(client)),
    labRuntimeApiProvider.overrideWithValue(api),
    courseRepositoryProvider.overrideWithValue(course),
    profileAccountGatewayProvider.overrideWithValue(FixtureProfile()),
    teacherPreferencesProvider(owner).overrideWith((ref) async => TeacherPreferences(setup: setup, uiLanguage: 'ru')),
  ]);
  container.read(appLocaleProvider.notifier).select(const Locale('ru'));
  runApp(UncontrolledProviderScope(container: container, child: const BuilderApp()));
  final preAuth = target == '/sign-in' || target == '/register' || target == '/recover-password';
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Deliver identity before navigating so the normal app router's guards apply.
    if (!preAuth) session.set(AuthenticatedSession(ownerId: owner, onboardingComplete: !target.startsWith('/onboarding')));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (target == '/onboarding/preferences' || target == '/onboarding/assistant') {
      final onb = container.read(onboardingControllerProvider(owner).notifier);
      onb.chooseSubject(SchoolSubject.mathematics);
      onb.toggleGrade(5);
      onb.setName(name);
    }
    container.read(appRouterProvider).go(target);
  });
}
