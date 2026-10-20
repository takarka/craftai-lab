import 'dart:convert';
import 'dart:io';

import 'package:builder/features/documents/infrastructure/builder_files_client.dart';
import 'package:crypto/crypto.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/builder_files/$name.json').readAsStringSync())
      as Map,
);

const artifactIdFor = '00000000-0000-4000-8000-000000000021';
const attachmentIdFor = '00000000-0000-4000-8000-000000000011';
const jobIdFor = '00000000-0000-4000-8000-000000000031';

/// Contract-shaped double of the attachment and document-job API. Responses are
/// derived from the contract fixtures; it keeps server-side state per
/// `Idempotency-Key`, so duplicates are observable.
class FakeFilesServer {
  final requests = <http.BaseRequest>[];
  final attachments = <String, Map<String, dynamic>>{};
  final jobs = <String, Map<String, dynamic>>{};
  final uploadBodies = <String>[];

  /// Fields and content type seen on the last multipart upload.
  Map<String, String> lastUploadFields = {};
  String? lastUploadContentType;
  List<int> lastUploadBytes = const [];

  /// Bytes the artifact endpoints serve; when set, the finished job lists an
  /// artifact whose size and SHA-256 describe exactly these bytes.
  List<int>? artifactContent;
  String artifactFormat = 'docx';
  bool artifactMetaExpired = false;

  /// Serve the content with a flipped byte, so size matches but the hash does not.
  bool corruptContent = false;

  /// Cut the connection after this many body bytes.
  int? dropAfterBytes;

  /// Send this many bytes and then wait until the client aborts.
  int? stallAfterBytes;
  bool ignoreRange = false;
  final ranges = <String?>[];
  int contentBytesSent = 0;

  int attachmentsCreated = 0;
  int jobsCreated = 0;

  /// Each of these makes the server process the request but lose the answer.
  bool dropNextUploadAnswer = false;
  bool dropNextJobAnswer = false;
  bool offline = false;

  /// Replaces a successful upload with this error (status, code).
  (int, String)? uploadError;
  bool rejectUploadedAttachment = false;
  String? jobFailsWith;

  /// Statuses a job reports on successive polls before it ends.
  List<String> script = ['queued', 'parsing', 'generating', 'assembling', 'succeeded'];
  int _polls = 0;
  bool jobExpired = false;
  bool cancelRequested = false;
  bool succeedWithoutArtifacts = false;

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  http.Response _body(Object body, int status) =>
      http.Response(jsonEncode(body), status, headers: _json);

  http.Response _error(int status, String code) => _body({
    'code': code,
    'type': status >= 500 ? 'Failure' : 'Validation',
    'message': 'error',
    'requestId': 'r',
  }, status);

  CraftAiClient get api => CraftAiClient(
    baseUri: Uri.parse('https://api.example.test'),
    httpClient: MockClient.streaming((request, bodyStream) async {
      requests.add(request);
      final bytes = await bodyStream.toBytes();
      final response = await handle(request, bytes);
      final isContent = request.url.path.endsWith('/content');
      return http.StreamedResponse(
        isContent ? _contentStream(request, response.bodyBytes) : Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        contentLength: response.bodyBytes.length,
        request: request,
      );
    }),
  );

  Stream<List<int>> _contentStream(http.BaseRequest request, List<int> body) async* {
    const chunk = 4096;
    for (var i = 0; i < body.length; i += chunk) {
      final end = (i + chunk).clamp(0, body.length);
      final limit = dropAfterBytes ?? stallAfterBytes;
      if (limit != null && i >= limit) {
        if (dropAfterBytes != null) throw const SocketException('connection lost');
        await (request as http.Abortable).abortTrigger;
        throw http.RequestAbortedException(request.url);
      }
      contentBytesSent += end - i;
      yield body.sublist(i, end);
    }
  }

  BuilderFilesClient get client => BuilderFilesClient(api);

  int count(String method, String pathPart) => requests
      .where((r) => r.method == method && r.url.path.contains(pathPart))
      .length;

  Future<http.Response> handle(http.BaseRequest request, List<int> body) async {
    if (offline) throw const SocketException('offline');
    final path = request.url.path;
    final method = request.method;

    if (method == 'POST' && path == '/builder/attachments') {
      final key = request.headers['Idempotency-Key']!;
      final existing = attachments[key];
      final text = utf8.decode(body, allowMalformed: true);
      lastUploadContentType = RegExp(r"content-type: (.+)").firstMatch(text)?.group(1)?.trim();
      lastUploadFields = {
        for (final m in RegExp(r'name="(\w+)"\r\n\r\n([^\r\n]*)\r\n').allMatches(text))
          m.group(1)!: m.group(2)!,
      };
      final fileName = RegExp(r'filename="([^"]*)"').firstMatch(text)?.group(1) ?? '';
      lastUploadBytes = body;
      if (uploadError != null) return _error(uploadError!.$1, uploadError!.$2);
      if (existing == null) {
        final attachment = fixture('Attachment.valid.0');
        attachmentsCreated++;
        attachment['id'] = attachmentsCreated == 1
            ? attachmentIdFor
            : '00000000-0000-4000-8000-0000000001${attachmentsCreated.toString().padLeft(2, '0')}';
        attachment['fileName'] = fileName;
        if (rejectUploadedAttachment) {
          attachment['status'] = 'rejected';
          attachment['rejectReason'] = 'file.encrypted';
        }
        attachments[key] = attachment;
      }
      if (dropNextUploadAnswer) {
        dropNextUploadAnswer = false;
        throw const SocketException('connection lost');
      }
      return _body(attachments[key]!, 201);
    }

    if (method == 'DELETE' && path.startsWith('/builder/attachments/')) {
      attachments.removeWhere((_, a) => path.endsWith(a['id'] as String));
      return http.Response('', 204);
    }

    if (method == 'POST' && path == '/builder/document-jobs') {
      final key = request.headers['Idempotency-Key']!;
      if (jobs[key] == null) {
        jobsCreated++;
        final job = fixture('DocumentJob.valid.0');
        job['id'] = jobIdFor;
        job['status'] = 'queued';
        job['artifacts'] = <Object>[];
        job.remove('progress');
        jobs[key] = job;
        _polls = 0;
      }
      if (dropNextJobAnswer) {
        dropNextJobAnswer = false;
        throw const SocketException('connection lost');
      }
      return _body(jobs[key]!, 202);
    }

    if (method == 'POST' && path.endsWith('/cancel')) {
      cancelRequested = true;
      return _body(jobs.values.first, 202);
    }

    if (method == 'DELETE' && path.startsWith('/builder/document-jobs/')) {
      jobs.clear();
      return http.Response('', 204);
    }

    if (method == 'GET' && path.startsWith('/builder/document-jobs/')) {
      if (jobExpired) return _error(404, 'job.not-found');
      final job = Map<String, dynamic>.from(jobs.values.first);
      if (cancelRequested) {
        job['status'] = 'canceled';
      } else if (jobFailsWith != null && _polls >= 1) {
        job['status'] = 'failed';
        job['error'] = {'code': jobFailsWith, 'message': 'x', 'retryable': true};
      } else {
        final status = script[_polls.clamp(0, script.length - 1)];
        _polls++;
        job['status'] = status;
        job['progress'] = status == 'succeeded' ? 100 : (_polls * 20).clamp(0, 99);
        if (status == 'succeeded' && !succeedWithoutArtifacts) {
          job['artifacts'] = artifactContent != null
              ? [artifactJson(artifactContent!)]
              : fixture('DocumentJob.valid.0')['artifacts'];
        }
      }
      return _body(job, 200);
    }

    if (method == 'GET' && path.startsWith('/builder/artifacts/')) {
      final content = artifactContent;
      if (content == null) return _error(404, 'artifact.not-found');
      if (artifactMetaExpired) return _error(410, 'artifact.expired');
      if (!path.endsWith('/content')) return _body(artifactJson(content), 200);
      var data = List<int>.of(content);
      if (corruptContent) data[data.length - 1] ^= 0xFF;
      final range = request.headers['Range'];
      ranges.add(range);
      final start = range == null ? 0 : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start > 0 && !ignoreRange) {
        return http.Response.bytes(
          data.sublist(start),
          206,
          headers: {'content-range': 'bytes $start-${data.length - 1}/${data.length}'},
        );
      }
      return http.Response.bytes(data, 200);
    }

    return _error(404, 'not-found');
  }

  /// Contract-shaped artifact describing [content].
  Map<String, dynamic> artifactJson(List<int> content) {
    final artifact = fixture('Artifact.valid.0');
    artifact['id'] = artifactIdFor;
    artifact['format'] = artifactFormat;
    artifact['fileName'] = 'example.$artifactFormat';
    artifact['mimeType'] = artifactFormat == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    artifact['sizeBytes'] = content.length;
    artifact['sha256'] = sha256.convert(content).toString();
    artifact['expiresAtUtc'] = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    return artifact;
  }
}
