import 'dart:async';
import 'package:builder/features/schedules/push/push_gateway.dart';
import 'package:builder/features/schedules/push/push_registration_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements PushGateway {
  @override
  bool configured = true;
  @override
  String platform = 'android';
  PushPermission allowed = PushPermission.granted;
  String? currentToken = 'token-one';
  int prompts = 0, deletes = 0;
  final tokenEvents = StreamController<String>.broadcast();
  final opened = StreamController<String>.broadcast();
  final foreground = StreamController<String>.broadcast();
  @override
  Stream<String> get tokens => tokenEvents.stream;
  @override
  Stream<String> get openedRuns => opened.stream;
  @override
  Stream<String> get foregroundRuns => foreground.stream;
  @override
  Future<PushPermission> permission({bool request = false}) async {
    if (request) prompts++;
    return allowed;
  }

  @override
  Future<String?> token() async => currentToken;
  @override
  Future<void> disable() async {
    deletes++;
  }

  Future<void> close() async {
    await tokenEvents.close();
    await opened.close();
    await foreground.close();
  }
}

class _Preferences implements PushPreferences {
  final values = <String, bool>{};
  final ids = <String, String>{};
  int sequence = 0;
  @override
  Future<bool> enabled(String owner) async => values[owner] ?? false;
  @override
  Future<void> setEnabled(String owner, bool value) async {
    values[owner] = value;
  }

  @override
  Future<String> installation(String owner) async =>
      ids.putIfAbsent(owner, () => 'installation-${sequence++}');
  @override
  Future<void> rotateInstallation(String owner) async {
    ids.remove(owner);
  }
}

class _Api implements BoundPushDeviceApi {
  final puts = <Map<String, dynamic>>[];
  final deletes = <String>[];
  bool failDelete = false;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<void> register(String id, Map<String, dynamic> input) async {
    puts.add({'id': id, ...input});
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
  }

  @override
  Future<void> revoke(String id) async {
    deletes.add(id);
    if (failDelete) throw StateError('offline');
  }
}

void main() {
  late _Gateway gateway;
  late _Preferences preferences;
  late Map<String, _Api> apis;
  late PushRegistrationService service;
  setUp(() {
    gateway = _Gateway();
    preferences = _Preferences();
    apis = {};
    service = PushRegistrationService(
      gateway: gateway,
      preferences: preferences,
      bindApi: (owner) async => apis.putIfAbsent(owner, _Api.new),
      appVersion: () async => '0.1.0+1',
    );
  });
  tearDown(() async {
    await service.dispose();
    await gateway.close();
  });
  test(
    'startup never prompts; opt-in registers version, locale and token',
    () async {
      await service.setOwner('alice', locale: 'kk');
      expect(gateway.prompts, 0);
      expect(apis['alice']!.puts, isEmpty);
      await service.enable();
      final sent = apis['alice']!.puts.single;
      expect(sent['locale'], 'kk');
      expect(sent['platform'], 'android');
      expect(sent['appVersion'], '0.1.0+1');
      expect(sent['pushToken'], 'token-one');
      expect(service.status, PushStatus.registered);
    },
  );
  test(
    'token rotation replaces registration using the same installation',
    () async {
      preferences.values['alice'] = true;
      await service.setOwner('alice');
      final originalId = apis['alice']!.puts.single['id'];
      gateway.currentToken = 'token-two';
      gateway.tokenEvents.add('token-two');
      await Future<void>.delayed(Duration.zero);
      await service.refresh();
      expect(apis['alice']!.puts.last['id'], originalId);
      expect(apis['alice']!.puts.last['pushToken'], 'token-two');
      expect(gateway.prompts, 0);
    },
  );
  test(
    'permission denial revokes a prior registration and does not generate a token',
    () async {
      preferences.values['alice'] = true;
      await service.setOwner('alice');
      gateway.allowed = PushPermission.denied;
      await service.refresh();
      expect(service.status, PushStatus.denied);
      expect(apis['alice']!.deletes, isNotEmpty);
      expect(apis['alice']!.puts.length, 1);
      expect(gateway.deletes, greaterThan(0));
    },
  );
  test(
    'offline opt-out is explicit and retried with the old installation',
    () async {
      preferences.values['alice'] = true;
      await service.setOwner('alice');
      final id = apis['alice']!.puts.single['id'];
      apis['alice']!.failDelete = true;
      await service.disable();
      expect(service.status, PushStatus.revokePending);
      expect(preferences.values['alice'], isFalse);
      expect(gateway.deletes, greaterThan(0));
      apis['alice']!.failDelete = false;
      await service.refresh();
      expect(apis['alice']!.deletes.last, id);
      expect(service.status, PushStatus.off);
    },
  );
  test(
    'account switch waits for the old PUT then revokes it as its owner',
    () async {
      preferences.values['alice'] = true;
      final alice = apis['alice'] = _Api()..gate = Completer<void>();
      final attaching = service.setOwner('alice');
      await alice.entered.future;
      final switching = service.setOwner('bob');
      alice.gate!.complete();
      await attaching;
      await switching;
      expect(alice.deletes, contains(alice.puts.single['id']));
      expect(apis['bob']!.puts, isEmpty);
      expect(gateway.prompts, 0);
    },
  );
  test(
    'taps are dropped after logout and new account defaults to off',
    () async {
      preferences.values['alice'] = true;
      await service.setOwner('alice');
      final events = <PushReadyEvent>[];
      final sub = service.events.listen(events.add);
      await service.detach();
      gateway.opened.add('run');
      await service.setOwner('bob');
      gateway.foreground.add('run');
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(apis['bob']!.puts, isEmpty);
      await sub.cancel();
    },
  );
  test('missing config stays unavailable and never prompts', () async {
    gateway.configured = false;
    await service.setOwner('alice');
    await service.enable();
    expect(service.status, PushStatus.unavailable);
    expect(gateway.prompts, 0);
    expect(apis, isEmpty);
  });
  test(
    'resume during logout cannot register until a new session event',
    () async {
      preferences.values['alice'] = true;
      await service.setOwner('alice');
      await service.detach();
      await service.setOwner('alice');
      expect(apis['alice']!.puts.length, 1);
      await service.setOwner('alice', sessionChanged: true);
      expect(apis['alice']!.puts.length, 2);
    },
  );
  test('payload accepts only run.ready and an opaque UUID, not a URL', () {
    const id = '00000000-0000-4000-8000-000000000051';
    expect(readyRunId({'type': 'run.ready', 'runId': id}), id);
    expect(
      readyRunId({'type': 'run.ready', 'runId': 'https://example.test'}),
      isNull,
    );
    expect(readyRunId({'type': 'open-url', 'runId': id}), isNull);
    expect(
      readyRunId({'type': 'run.ready', 'runId': '../another-owner'}),
      isNull,
    );
  });
}
