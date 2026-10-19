import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

enum PushPermission { granted, denied, unavailable }

abstract class PushGateway {
  bool get configured;
  String get platform;
  Stream<String> get tokens;
  Stream<String> get openedRuns;
  Stream<String> get foregroundRuns;
  Future<PushPermission> permission({bool request = false});
  Future<String?> token();
  Future<void> disable();
}

String? readyRunId(Map<String, dynamic> data) {
  final id = data['runId'];
  return data['type'] == 'run.ready' &&
          id is String &&
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(id)
      ? id
      : null;
}

class FirebasePushGateway implements PushGateway {
  final _tokens = StreamController<String>.broadcast();
  final _opened = StreamController<String>.broadcast();
  final _foreground = StreamController<String>.broadcast();
  final _subscriptions = <StreamSubscription>[];
  Future<FirebaseMessaging?>? _initializing;

  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  @override
  bool get configured =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      const bool.fromEnvironment('FIREBASE_PUSH_ENABLED');

  @override
  Stream<String> get tokens => _tokens.stream;
  @override
  Stream<String> get openedRuns => _opened.stream;
  @override
  Stream<String> get foregroundRuns => _foreground.stream;

  Future<FirebaseMessaging?> _messaging() => _initializing ??= _initialize();
  Future<FirebaseMessaging?> _initialize() async {
    if (!configured) return null;
    // Native config is also required when the process is terminated.
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    // Backend HTTP v1 currently accepts legacy registration tokens, not FIDs.
    // Keep these APIs until the backend direct-send contract migrates too.
    _subscriptions.add(
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen(_tokens.add, onError: (_) {}),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final id = readyRunId(message.data);
        if (id != null) _opened.add(id);
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((message) {
        final id = readyRunId(message.data);
        if (id != null) _foreground.add(id);
      }),
    );
    // No foreground OS alert: the application displays one neutral in-app notice.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    return messaging;
  }

  bool _initialConsumed = false;
  @override
  Future<PushPermission> permission({bool request = false}) async {
    final messaging = await _messaging();
    if (messaging == null) return PushPermission.unavailable;
    final settings = request
        ? await messaging.requestPermission(
            alert: true,
            badge: false,
            sound: true,
          )
        : await messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional
        ? PushPermission.granted
        : PushPermission.denied;
  }

  @override
  Future<String?> token() async {
    final messaging = await _messaging();
    if (messaging == null) return null;
    // APNs can arrive later: resume/manual refresh retries without requesting permission.
    if (platform == 'ios' && await messaging.getAPNSToken() == null) {
      return null;
    }
    await messaging.setAutoInitEnabled(true);
    // ignore: deprecated_member_use
    final token = await messaging.getToken();
    if (!_initialConsumed) {
      _initialConsumed = true;
      final initial = await messaging.getInitialMessage();
      final id = initial == null ? null : readyRunId(initial.data);
      if (id != null) _opened.add(id);
    }
    return token;
  }

  @override
  Future<void> disable() async {
    final messaging = await _messaging();
    if (messaging == null) return;
    await messaging.setAutoInitEnabled(false);
    // ignore: deprecated_member_use
    await messaging.deleteToken();
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _tokens.close();
    await _opened.close();
    await _foreground.close();
  }
}
