import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/infrastructure/craft_ai_client.dart';
import 'push_gateway.dart';

enum PushStatus {
  off,
  unavailable,
  denied,
  waitingForToken,
  registered,
  failed,
  revokePending,
}

class PushReadyEvent {
  const PushReadyEvent(this.ownerId, this.runId, {required this.opened});
  final String ownerId, runId;
  final bool opened;
}

abstract class PushPreferences {
  Future<bool> enabled(String owner);
  Future<void> setEnabled(String owner, bool value);
  Future<String> installation(String owner);
  Future<void> rotateInstallation(String owner);
}

class SecurePushPreferences implements PushPreferences {
  const SecurePushPreferences();
  static const _storage = FlutterSecureStorage();
  @override
  Future<bool> enabled(String owner) async =>
      await _storage.read(key: 'push.enabled.$owner') == 'true';
  @override
  Future<void> setEnabled(String owner, bool value) =>
      _storage.write(key: 'push.enabled.$owner', value: '$value');
  @override
  Future<String> installation(String owner) async {
    final key = 'push.installation.$owner';
    final saved = await _storage.read(key: key);
    if (saved != null) return saved;
    final id = CraftAiClient.generateRequestId();
    await _storage.write(key: key, value: id);
    return id;
  }

  @override
  Future<void> rotateInstallation(String owner) =>
      _storage.delete(key: 'push.installation.$owner');
}

/// Its HTTP authorization is captured for one owner. Never refresh as a new owner.
abstract class BoundPushDeviceApi {
  Future<void> register(String id, Map<String, dynamic> input);
  Future<void> revoke(String id);
}

class PushRegistrationService {
  PushRegistrationService({
    required this.gateway,
    required this.preferences,
    required this.bindApi,
    required this.appVersion,
  }) {
    _subscriptions.add(
      gateway.tokens.listen((_) {
        unawaited(refresh());
      }),
    );
    _subscriptions.add(gateway.openedRuns.listen((id) => _ready(id, true)));
    _subscriptions.add(
      gateway.foregroundRuns.listen((id) => _ready(id, false)),
    );
  }
  final PushGateway gateway;
  final PushPreferences preferences;
  final Future<BoundPushDeviceApi?> Function(String owner) bindApi;
  final Future<String> Function() appVersion;
  final _states = StreamController<PushStatus>.broadcast();
  final _events = StreamController<PushReadyEvent>.broadcast();
  final _subscriptions = <StreamSubscription>[];
  Stream<PushStatus> get states => _states.stream;
  Stream<PushReadyEvent> get events => _events.stream;
  PushStatus status = PushStatus.off;
  String? _owner;
  String? _detachedOwner;
  String _locale = 'ru';
  int _epoch = 0;
  bool _enabled = false, _disposed = false;
  ({String owner, String installation, BoundPushDeviceApi api})? _registration;
  Future<void> _tail = Future.value();

  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _status(PushStatus value) {
    if (_disposed) return;
    status = value;
    _states.add(value);
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch && _owner != null;
  void _ready(String id, bool opened) {
    if (!_disposed && _enabled && _owner != null) {
      _events.add(PushReadyEvent(_owner!, id, opened: opened));
    }
  }

  Future<void> setOwner(
    String? owner, {
    String locale = 'ru',
    bool sessionChanged = false,
  }) {
    if (sessionChanged) _detachedOwner = null;
    if (owner != null && owner == _detachedOwner) return Future.value();
    _locale = locale;
    if (_owner == owner) {
      return owner == null ? _serial(() => _revoke(null)) : refresh();
    }
    final previous = _owner;
    final epoch = ++_epoch;
    _owner = owner;
    _enabled = false;
    _status(PushStatus.off);
    return _serial(() async {
      try {
        if (previous != null) await _revoke(previous);
        if (!_current(epoch)) return;
        if (!gateway.configured) {
          _status(PushStatus.unavailable);
          return;
        }
        final enabled = await preferences.enabled(owner!);
        if (!_current(epoch)) return;
        _enabled = enabled;
        await _sync(epoch);
      } catch (_) {
        if (_current(epoch)) _status(PushStatus.failed);
      }
    });
  }

  Future<void> refresh({String? locale}) {
    if (locale != null) _locale = locale;
    final epoch = _epoch;
    return _serial(() async {
      if (_current(epoch)) await _sync(epoch);
    });
  }

  Future<void> enable() {
    final epoch = _epoch;
    return _serial(() async {
      if (!_current(epoch)) return;
      try {
        if (!gateway.configured) {
          _status(PushStatus.unavailable);
          return;
        }
        final permission = await gateway.permission(request: true);
        if (!_current(epoch)) return;
        if (permission != PushPermission.granted) {
          await _revoke(_owner);
          if (!_current(epoch) || status == PushStatus.revokePending) return;
          _status(
            permission == PushPermission.unavailable
                ? PushStatus.unavailable
                : PushStatus.denied,
          );
          return;
        }
        await preferences.setEnabled(_owner!, true);
        if (!_current(epoch)) return;
        _enabled = true;
        await _sync(epoch);
      } catch (_) {
        if (_current(epoch)) _status(PushStatus.failed);
      }
    });
  }

  Future<void> disable() {
    final owner = _owner;
    final epoch = ++_epoch;
    _enabled = false;
    return _serial(() async {
      var preferenceFailed = false;
      try {
        if (owner != null) await preferences.setEnabled(owner, false);
      } catch (_) {
        preferenceFailed = true;
      }
      await _revoke(owner);
      if (_current(epoch)) {
        _status(
          preferenceFailed || status == PushStatus.revokePending
              ? PushStatus.revokePending
              : PushStatus.off,
        );
      }
    });
  }

  /// Called before credentials are cleared/replaced; also handles offline logout.
  Future<void> detach() {
    final previous = _owner ?? _detachedOwner;
    final detached = setOwner(null);
    // A lifecycle resume while logout is in progress must not re-register.
    _detachedOwner = previous;
    return detached;
  }

  Future<void> _sync(int epoch) async {
    try {
      if (!gateway.configured) {
        _status(PushStatus.unavailable);
        return;
      }
      if (!_enabled) {
        // Also retries an unconfirmed offline opt-out after a restart/resume.
        await _revoke(_owner);
        return;
      }
      final permission = await gateway.permission();
      if (!_current(epoch)) return;
      if (permission != PushPermission.granted) {
        await _revoke(_owner);
        if (_current(epoch) && status != PushStatus.revokePending) {
          _status(PushStatus.denied);
        }
        return;
      }
      final token = await gateway.token();
      if (!_current(epoch)) return;
      if (token == null || token.isEmpty) {
        _status(PushStatus.waitingForToken);
        return;
      }
      final owner = _owner!;
      final api = await bindApi(owner);
      if (!_current(epoch)) return;
      if (api == null) {
        _status(PushStatus.failed);
        return;
      }
      final installation = await preferences.installation(owner);
      if (!_current(epoch)) return;
      final version = await appVersion();
      if (!_current(epoch)) return;
      // Set before the PUT: even a lost response must be revoked on detach.
      _registration = (owner: owner, installation: installation, api: api);
      await api.register(installation, {
        'platform': gateway.platform,
        'pushToken': token,
        'locale': _locale,
        'appVersion': version,
      });
      if (_current(epoch)) _status(PushStatus.registered);
    } catch (_) {
      if (_current(epoch)) _status(PushStatus.failed);
    }
  }

  Future<void> _revoke(String? owner) async {
    var failed = false;
    final registration = _registration;
    _registration = null;
    try {
      if (registration != null) {
        final freshApi = await bindApi(registration.owner);
        await (freshApi ?? registration.api).revoke(registration.installation);
      } else if (owner != null) {
        final api = await bindApi(owner);
        if (api != null) {
          await api.revoke(await preferences.installation(owner));
        } else {
          failed = true;
        }
      }
    } catch (_) {
      _registration = registration;
      failed = true;
    }
    try {
      await gateway.disable();
    } catch (_) {
      failed = true;
    }
    if (owner != null && !failed) {
      try {
        await preferences.rotateInstallation(owner);
      } catch (_) {
        failed = true;
      }
    }
    _status(failed ? PushStatus.revokePending : PushStatus.off);
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _tail;
    await _states.close();
    await _events.close();
  }
}
