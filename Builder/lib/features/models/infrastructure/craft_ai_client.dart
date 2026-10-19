import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../session/infrastructure/secure_token_storage.dart';

sealed class CraftAiException implements Exception {
  const CraftAiException(this.message, {this.statusCode, this.requestId});
  final String message;
  final int? statusCode;
  final String? requestId;

  @override
  String toString() =>
      '$runtimeType: $message${statusCode != null ? ' (Status: $statusCode)' : ''}${requestId != null ? ' [Request-ID: $requestId]' : ''}';
}

final class CraftAiAuthException extends CraftAiException {
  const CraftAiAuthException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
}

final class CraftAiForbiddenException extends CraftAiException {
  const CraftAiForbiddenException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
}

final class CraftAiServerException extends CraftAiException {
  const CraftAiServerException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
}

final class CraftAiNetworkException extends CraftAiException {
  const CraftAiNetworkException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
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
        final request = http.Request(method, url)
          ..headers.addAll(requestHeaders);
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
        return jsonDecode(bodyText) as Map<String, dynamic>;
      }

      if (status == 401) {
        throw CraftAiAuthException(
          'Unauthorized: session expired or token missing.',
          statusCode: status,
          requestId: requestId,
        );
      }

      if (status == 403) {
        throw CraftAiForbiddenException(
          'Access forbidden.',
          statusCode: status,
          requestId: requestId,
        );
      }

      if (status >= 500) {
        throw CraftAiServerException(
          'CraftAI server error occurred.',
          statusCode: status,
          requestId: requestId,
        );
      }

      throw CraftAiServerException(
        'Unexpected response status $status',
        statusCode: status,
        requestId: requestId,
      );
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

  void close() {
    _httpClient.close();
  }
}
