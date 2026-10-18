import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/storage/storage_providers.dart';
import '../onboarding/domain/initial_workspace_repository.dart';
import '../session/session_repository.dart';
import 'domain/profile.dart';
import 'infrastructure/profile_store.dart';

final profileStoreProvider = Provider<ProfileStore?>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  final workspace = ref.watch(workspaceStorageServiceProvider);
  return db == null || workspace == null
      ? null
      : ProfileStore(database: db, workspace: workspace);
});

final profileAccountGatewayProvider = Provider<ProfileAccountGateway>(
  (ref) => const UnavailableProfileAccountGateway(),
);

bool isProfileOwner(SessionSnapshot? session, String ownerId) {
  return session is AuthenticatedSession && session.ownerId == ownerId;
}

final teacherPreferencesProvider = FutureProvider.autoDispose
    .family<TeacherPreferences?, String>((ref, ownerId) async {
      final session = ref.watch(sessionProvider).asData?.value;
      if (session is! AuthenticatedSession || session.ownerId != ownerId) {
        return null;
      }
      final store = ref.watch(profileStoreProvider);
      if (store == null) {
        throw StateError('Local profile storage is not available');
      }
      final preferences = await store.readPreferences(ownerId);
      return ref.mounted &&
              isProfileOwner(ref.read(sessionProvider).asData?.value, ownerId)
          ? preferences
          : null;
    });

final profileAccountProvider = StreamProvider.autoDispose
    .family<ProfileAccountState, String>((ref, ownerId) async* {
      final session = ref.watch(sessionProvider).asData?.value;
      if (session is! AuthenticatedSession || session.ownerId != ownerId) {
        return;
      }
      final store = ref.watch(profileStoreProvider);
      final gateway = ref.watch(profileAccountGatewayProvider);
      var active = true;
      ref.onDispose(() => active = false);
      final epoch = store?.workspace.activeEpoch;
      bool current() =>
          active &&
          isProfileOwner(ref.read(sessionProvider).asData?.value, ownerId) &&
          (store == null ||
              (store.workspace.activeOwnerId == ownerId &&
                  store.workspace.activeEpoch == epoch));
      AccountSnapshot? cached;
      try {
        cached = await store?.readSnapshot(ownerId);
      } catch (_) {
        // A damaged cache must not prevent a fresh server read.
      }
      if (!current()) return;
      yield ProfileAccountState(
        snapshot: cached,
        cached: cached != null,
        unavailable: !gateway.isAvailable,
      );
      if (!gateway.isAvailable) return;
      try {
        final snapshot = await gateway.load(ownerId);
        if (!current()) return;
        if (snapshot.ownerId != ownerId) {
          throw const FormatException('Account owner mismatch');
        }
        try {
          await store?.saveSnapshot(
            snapshot,
            WorkspaceWritePermit(ownerId: ownerId, canCommit: current),
          );
        } catch (_) {
          // Fresh confirmed data remains usable when the local cache cannot be written.
        }
        if (current()) yield ProfileAccountState(snapshot: snapshot);
      } catch (_) {
        if (current()) {
          yield ProfileAccountState(
            snapshot: cached,
            cached: cached != null,
            unavailable: true,
          );
        }
      }
    });

/// Restores the saved UI locale per account without changing assistant language.
final profileLocaleRestoreProvider = Provider<void>((ref) {
  final session = ref.watch(sessionProvider).asData?.value;
  if (session is! AuthenticatedSession) return;
  ref.listen(teacherPreferencesProvider(session.ownerId), (_, next) {
    final language = next.asData?.value?.uiLanguage;
    if (language != null && const ['ru', 'kk'].contains(language)) {
      scheduleMicrotask(() {
        if (ref.mounted &&
            isProfileOwner(
              ref.read(sessionProvider).asData?.value,
              session.ownerId,
            )) {
          ref.read(appLocaleProvider.notifier).select(Locale(language));
        }
      });
    }
  }, fireImmediately: true);
});
