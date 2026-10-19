import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import '../../session/infrastructure/secure_token_storage.dart';

sealed class CraftAiException implements Exception {
  const CraftAiException(
    this.message, {
    this.statusCode,
    this.requestId,
    this.code,
  });
  final String message;
  final int? statusCode;
  final String? requestId;

  /// Domain error code from the `ErrorResponse` body, e.g. `file.no-text-layer`.
  final String? code;

  @override
  String toString() =>
      '$runtimeType: $message${statusCode != null ? ' (Status: $statusCode)' : ''}${requestId != null ? ' [Request-ID: $requestId]' : ''}';
}

final class CraftAiAuthException extends CraftAiException {
  const CraftAiAuthException(
    super.message, {
    super.statusCode,
    super.requestId,
    super.code,
  });
}

final class CraftAiForbiddenException extends CraftAiException {
  const CraftAiForbiddenException(
    super.message, {
    super.statusCode,
    super.requestId,
    super.code,
  });
}

final class CraftAiServerException extends CraftAiException {
  const CraftAiServerException(
    super.message, {
    super.statusCode,
    super.requestId,
    super.code,
  });
}

/// The caller aborted the request; nothing is wrong with the connection.
final class CraftAiCancelledException extends CraftAiException {
  const CraftAiCancelledException(super.message, {super.requestId});
}

final class CraftAiNetworkException extends CraftAiException {
  const CraftAiNetworkException(
    super.message, {
    super.statusCode,
    super.requestId,
    super.code,
  });
}

/// A file sent as `multipart/form-data`; rebuilt for the token-refresh retry.
class UploadFile {
  const UploadFile({
    required this.field,
    required this.fileName,
    required this.bytes,
    required this.contentType,
  });
  final String field;
  final String fileName;
  final List<int> bytes;
  final String contentType;
}

class CraftAiClient {
  CraftAiClient({
    required this.baseUri,
    http.Client? httpClient,
    this.tokenStorage,
  }) : _httpClient = httpClient ?? http.Client();

  final Uri baseUri;
  final http.Client _httpClient;
  final SecureTokenStorage? tokenStorage;

  static String generateRequestId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    // Set version 4 and variant RFC 4122
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) => requestJson('GET', path, headers: headers, timeout: timeout);

  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
    Future<void>? abortTrigger,
    UploadFile? upload,
    Map<String, String>? fields,
  }) async {
    final requestId = generateRequestId();
    final url = baseUri.resolve(path);

    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'X-Request-Id': requestId,
      if (body != null) 'Content-Type': 'application/json',
      if (headers != null) ...headers,
    };

    try {
      var tokens = tokenStorage == null
          ? null
          : await tokenStorage!.readTokens();
      if (tokens != null) {
        requestHeaders['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
      Future<http.Response> send() async {
        if (upload != null) {
          final request =
              http.AbortableMultipartRequest(
                  method,
                  url,
                  abortTrigger: abortTrigger,
                )
                ..headers.addAll(requestHeaders)
                ..fields.addAll(fields ?? const {})
                ..files.add(
                  http.MultipartFile.fromBytes(
                    upload.field,
                    upload.bytes,
                    filename: upload.fileName,
                    contentType: MediaType.parse(upload.contentType),
                  ),
                );
          return http.Response.fromStream(await _httpClient.send(request));
        }
        final request = http.AbortableRequest(
          method,
          url,
          abortTrigger: abortTrigger,
        )..headers.addAll(requestHeaders);
        if (body != null) request.body = jsonEncode(body);
        return http.Response.fromStream(await _httpClient.send(request));
      }

      var response = await send().timeout(timeout);

      // A request is retried once after the shared refresh operation. This is
      // required even when a server invalidates a token before its expiry.
      if (response.statusCode == 401 && tokenStorage != null) {
        tokens = await tokenStorage!.refreshTokens();
        if (tokens != null) {
          requestHeaders['Authorization'] = 'Bearer ${tokens.accessToken}';
          response = await send().timeout(timeout);
        }
      }

      final status = response.statusCode;
      final bodyText = response.body;

      if (status >= 200 && status < 300) {
        if (bodyText.isEmpty) return <String, dynamic>{};
        try {
          return jsonDecode(bodyText) as Map<String, dynamic>;
        } on FormatException {
          throw CraftAiServerException(
            'Response is not valid JSON.',
            statusCode: status,
            requestId: requestId,
          );
        } on TypeError {
          throw CraftAiServerException(
            'Response is not a JSON object.',
            statusCode: status,
            requestId: requestId,
          );
        }
      }

      final errorCode = _errorCode(bodyText);
      if (status == 401) {
        throw CraftAiAuthException(
          'Unauthorized: session expired or token missing.',
          statusCode: status,
          requestId: requestId,
          code: errorCode,
        );
      }

      if (status == 403) {
        throw CraftAiForbiddenException(
          'Access forbidden.',
          statusCode: status,
          requestId: requestId,
          code: errorCode,
        );
      }

      if (status >= 500) {
        throw CraftAiServerException(
          'CraftAI server error occurred.',
          statusCode: status,
          requestId: requestId,
          code: errorCode,
        );
      }

      throw CraftAiServerException(
        'Unexpected response status $status',
        statusCode: status,
        requestId: requestId,
        code: errorCode,
      );
    } on http.RequestAbortedException {
      throw CraftAiCancelledException('Request cancelled.', requestId: requestId);
    } on SocketException {
      throw CraftAiNetworkException(
        'Network unavailable or connection failed.',
        requestId: requestId,
      );
    } on HandshakeException {
      throw CraftAiNetworkException(
        'Secure TLS connection failed.',
        requestId: requestId,
      );
    } on TimeoutException {
      throw CraftAiNetworkException(
        'Request timed out after ${timeout.inSeconds} seconds.',
        requestId: requestId,
      );
    } on CraftAiException {
      rethrow;
    } catch (e) {
      throw CraftAiNetworkException('Network error: $e', requestId: requestId);
    }
  }

  static String? _errorCode(String bodyText) {
    try {
      final decoded = jsonDecode(bodyText);
      final code = decoded is Map ? decoded['code'] : null;
      return code is String && code.length <= 100 ? code : null;
    } catch (_) {
      return null;
    }
  }

  void close() {
    _httpClient.close();
  }
}
