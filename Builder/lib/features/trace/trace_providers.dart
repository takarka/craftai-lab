import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/storage/storage_providers.dart';
import '../session/session_repository.dart';
import 'domain/request_trace.dart';
import 'domain/trace_repository.dart';
import 'infrastructure/persistent_trace_repository.dart';

final traceRepositoryProvider = Provider<TraceRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  final session = ref.watch(sessionProvider).asData?.value;
  if (db == null || session is! AuthenticatedSession) {
    return InMemoryTraceRepository();
  }
  return PersistentTraceRepository.fromStorage(
    storageDatabase: db,
    ownerId: session.ownerId,
  );
});

final traceProvider = FutureProvider.family<RequestTrace?, String>((
  ref,
  requestId,
) async {
  final repo = ref.watch(traceRepositoryProvider);
  if (requestId == 'sample' || requestId == 'sample-trace-748') {
    return repo.getSampleTrace();
  }
  return repo.getTrace(requestId);
});
