import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../session/infrastructure/secure_token_storage.dart';
import '../domain/lab_agent.dart';

class LabApiClient {
  LabApiClient({
    required this.baseUri,
    required this.client,
    required this.tokens,
    required this.ownerId,
  });
  final Uri baseUri;
  final http.Client client;
  final SecureTokenStorage tokens;
  final String ownerId;

  Future<void> _checkOwner() async {
    if (await tokens.readOwnerId() != ownerId) {
      throw const LabApiException('session.changed', status: 401);
    }
  }

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    await _checkOwner();
    var auth = await tokens.readTokens();
    if (auth == null || auth.isExpired) auth = await tokens.refreshTokens();
    await _checkOwner();
    if (auth == null) {
      throw const LabApiException('session.expired', status: 401);
    }
    try {
      final request = http.Request(method, baseUri.resolve('/lab/v1/$path'));
      request.headers.addAll({
        'Accept': 'application/json',
        'Authorization': '${auth.tokenType} ${auth.accessToken}',
      });
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 20));
      await _checkOwner();
      if (response.statusCode == 204) return null;
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw LabApiException('response.invalid', status: response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = data is Map ? (data['error'] ?? data) : null;
        throw LabApiException(
          error is Map
              ? error['code'] as String? ?? 'request.failed'
              : 'request.failed',
          status: response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const LabApiException('network.unavailable');
    } on SocketException {
      throw const LabApiException('network.unavailable');
    } on http.ClientException {
      throw const LabApiException('network.unavailable');
    }
  }

  Future<List<LabAgent>> listAgents() async {
    final data = await request('GET', 'agents') as Map<String, dynamic>;
    return (data['agents'] as List)
        .map((row) => LabAgent(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<LabAgent> create(Map<String, dynamic> config) async =>
      LabAgent(await request('POST', 'agents', config) as Map<String, dynamic>);
  Future<LabAgent> update(String id, Map<String, dynamic> changes) async =>
      LabAgent(
        await request('PATCH', 'agents/${Uri.encodeComponent(id)}', changes)
            as Map<String, dynamic>,
      );
  Future<LabAgent> copy(String id, String name) async => LabAgent(
    await request('POST', 'agents/${Uri.encodeComponent(id)}/copy', {
          'name': name,
        })
        as Map<String, dynamic>,
  );
  Future<LabAgent> reset(String id) async => LabAgent(
    await request('POST', 'agents/${Uri.encodeComponent(id)}/reset')
        as Map<String, dynamic>,
  );
  Future<void> delete(String id) async =>
      request('DELETE', 'agents/${Uri.encodeComponent(id)}');
}
