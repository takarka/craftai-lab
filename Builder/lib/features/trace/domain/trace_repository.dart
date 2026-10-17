import 'request_trace.dart';

abstract class TraceRepository {
  Future<RequestTrace?> getTrace(String requestId);
  Future<void> saveTrace(RequestTrace trace);
  Future<RequestTrace> getSampleTrace({String? languageCode});
}
