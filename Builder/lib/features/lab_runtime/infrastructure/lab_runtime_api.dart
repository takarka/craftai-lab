import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/lab_run_models.dart';

abstract class LabRuntimeApi {
  Future<List<LabModelInfo>> listModels() async => const [];

  Future<LabRun> createRun({
    required String agentId,
    required String prompt,
    required String idempotencyKey,
    List<String> imageDataUris = const [],
  });

  Future<LabRun> getRun(String runId);

  Future<LabRun> cancelRun(String runId);

  Future<LabRun> resolveAction({
    required String runId,
    required String actionId,
    required String decision,
    Map<String, dynamic>? params,
  });

  Future<List<LabMaterialItem>> listMaterials(String agentId);

  Future<LabMaterialItem> createMaterial({
    required String agentId,
    required String title,
    required String content,
    String source = 'text',
  });

  Future<void> deleteMaterial({
    required String agentId,
    required String materialId,
  });

  Future<LabPhotoExtraction> uploadPhoto({
    required String agentId,
    required String fileName,
    required List<int> bytes,
  });

  Future<List<LabMemoryItem>> listMemory(String agentId);

  Future<LabMemoryItem> createMemory({
    required String agentId,
    required String content,
  });

  Future<void> deleteMemory({required String agentId, required String entryId});

  Future<List<LabSkillItem>> listSkills(String agentId);

  Future<LabSkillItem> updateSkill({
    required String agentId,
    required String slug,
    required bool enabled,
    required String overrideText,
    required bool allowSave,
    required bool allowSearch,
  });
}

abstract interface class LabDialogueApi {
  Future<LabDialoguePage> getDialogue(String agentId, {String? before});

  Future<LabRun> createDialogueTurn({
    required String agentId,
    required String conversationId,
    required String prompt,
    required String idempotencyKey,
    List<String> imageDataUris = const [],
  });
}

class HttpLabRuntimeApi implements LabRuntimeApi, LabDialogueApi {
  final http.Client client;
  final Uri baseUri;
  final Future<String?> Function() getAccessToken;

  HttpLabRuntimeApi({
    required this.client,
    required this.baseUri,
    required this.getAccessToken,
  });

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (idempotencyKey != null && idempotencyKey.isNotEmpty)
        'Idempotency-Key': idempotencyKey,
    };
  }

  Uri _uri(String path) => baseUri.resolve(path);

  Never _throwFromResponse(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final code = (decoded['code'] as String?) ?? 'http.${resp.statusCode}';
      final message =
          (decoded['message'] as String?) ??
          'Ошибка сервера (${resp.statusCode}).';
      throw LabApiException(
        code: code,
        message: message,
        nextStep: _nextStepForCode(code),
      );
    } on LabApiException {
      rethrow;
    } catch (_) {
      throw LabApiException(
        code: 'http.${resp.statusCode}',
        message: 'Сервер вернул ошибку (${resp.statusCode}).',
      );
    }
  }

  String _nextStepForCode(String code) {
    return switch (code) {
      'model.incompatible-vision' || 'model.incompatible-tools' =>
        'Откройте настройки агента и выберите совместимую модель.',
      'budget.exceeded' =>
        'Лимит расходов пилота исчерпан. Обратитесь к организатору.',
      'action.expired' =>
        'Повторите запрос, чтобы получить новое подтверждение.',
      _ => 'Нажмите «Повторить» или проверьте параметры агента.',
    };
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    try {
      final uri = _uri(path);
      final headers = await _headers(idempotencyKey: idempotencyKey);
      late http.Response resp;
      if (method == 'GET') {
        resp = await client.get(uri, headers: headers);
      } else if (method == 'POST') {
        resp = await client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      } else if (method == 'PUT') {
        resp = await client.put(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      } else if (method == 'DELETE') {
        resp = await client.delete(uri, headers: headers);
      } else {
        throw UnsupportedError('Unsupported method $method');
      }

      if (resp.statusCode >= 400) {
        _throwFromResponse(resp);
      }
      if (resp.body.isEmpty) {
        return const <String, dynamic>{};
      }
      return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    } on SocketException {
      throw const LabApiException(
        code: 'network.offline',
        message: 'Нет подключения к сети. Черновик сохранён локально.',
        nextStep: 'Восстановите интернет и нажмите «Повторить».',
        isOffline: true,
      );
    }
  }

  @override
  Future<List<LabModelInfo>> listModels() async {
    final data = await _sendJson('GET', '/lab/v1/models');
    final items = (data['models'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => LabModelInfo.fromJson(Map<String, dynamic>.from(e)))
        .where((m) => m.available && m.modelId.isNotEmpty)
        .toList();
  }

  @override
  Future<LabRun> createRun({
    required String agentId,
    required String prompt,
    required String idempotencyKey,
    List<String> imageDataUris = const [],
  }) async {
    final data = await _sendJson(
      'POST',
      '/lab/v1/agents/$agentId/runs',
      idempotencyKey: idempotencyKey,
      body: {'prompt': prompt, 'image_data_uris': imageDataUris},
    );
    return LabRun.fromJson(data);
  }

  @override
  Future<LabDialoguePage> getDialogue(String agentId, {String? before}) async {
    final query = before == null
        ? ''
        : '?before=${Uri.encodeQueryComponent(before)}';
    final data = await _sendJson(
      'GET',
      '/lab/v1/agents/$agentId/dialogue$query',
    );
    return LabDialoguePage.fromJson(data);
  }

  @override
  Future<LabRun> createDialogueTurn({
    required String agentId,
    required String conversationId,
    required String prompt,
    required String idempotencyKey,
    List<String> imageDataUris = const [],
  }) async {
    final data = await _sendJson(
      'POST',
      '/lab/v1/agents/$agentId/runs',
      idempotencyKey: idempotencyKey,
      body: {
        'dialogue': true,
        'conversation_id': conversationId,
        'prompt': prompt,
        'image_data_uris': imageDataUris,
      },
    );
    return LabRun.fromJson(data);
  }

  @override
  Future<LabRun> getRun(String runId) async {
    final data = await _sendJson('GET', '/lab/v1/runs/$runId');
    return LabRun.fromJson(data);
  }

  @override
  Future<LabRun> cancelRun(String runId) async {
    final data = await _sendJson('POST', '/lab/v1/runs/$runId/cancel');
    return LabRun.fromJson(data);
  }

  @override
  Future<LabRun> resolveAction({
    required String runId,
    required String actionId,
    required String decision,
    Map<String, dynamic>? params,
  }) async {
    final data = await _sendJson(
      'POST',
      '/lab/v1/runs/$runId/actions/$actionId',
      body: {'decision': decision, if (params != null) 'params': params},
    );
    return LabRun.fromJson(data);
  }

  @override
  Future<List<LabMaterialItem>> listMaterials(String agentId) async {
    final data = await _sendJson('GET', '/lab/v1/agents/$agentId/materials');
    final items = (data['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => LabMaterialItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<LabMaterialItem> createMaterial({
    required String agentId,
    required String title,
    required String content,
    String source = 'text',
  }) async {
    final data = await _sendJson(
      'POST',
      '/lab/v1/agents/$agentId/materials',
      body: {'title': title, 'content': content, 'source': source},
    );
    return LabMaterialItem.fromJson(data);
  }

  @override
  Future<void> deleteMaterial({
    required String agentId,
    required String materialId,
  }) async {
    await _sendJson('DELETE', '/lab/v1/agents/$agentId/materials/$materialId');
  }

  @override
  Future<LabPhotoExtraction> uploadPhoto({
    required String agentId,
    required String fileName,
    required List<int> bytes,
  }) async {
    try {
      final token = await getAccessToken();
      final req = http.MultipartRequest(
        'POST',
        _uri('/lab/v1/agents/$agentId/photos'),
      );
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
      final streamed = await client.send(req);
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode >= 400) {
        _throwFromResponse(resp);
      }
      return LabPhotoExtraction.fromJson(
        Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
      );
    } on SocketException {
      throw const LabApiException(
        code: 'network.offline',
        message: 'Нет сети при загрузке фото. Черновик сохранён.',
        isOffline: true,
      );
    }
  }

  @override
  Future<List<LabMemoryItem>> listMemory(String agentId) async {
    final data = await _sendJson('GET', '/lab/v1/agents/$agentId/memory');
    final items = (data['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => LabMemoryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<LabMemoryItem> createMemory({
    required String agentId,
    required String content,
  }) async {
    final data = await _sendJson(
      'POST',
      '/lab/v1/agents/$agentId/memory',
      body: {'content': content},
    );
    return LabMemoryItem.fromJson(data);
  }

  @override
  Future<void> deleteMemory({
    required String agentId,
    required String entryId,
  }) async {
    await _sendJson('DELETE', '/lab/v1/agents/$agentId/memory/$entryId');
  }

  @override
  Future<List<LabSkillItem>> listSkills(String agentId) async {
    final data = await _sendJson('GET', '/lab/v1/agents/$agentId/skills');
    final items = (data['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => LabSkillItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<LabSkillItem> updateSkill({
    required String agentId,
    required String slug,
    required bool enabled,
    required String overrideText,
    required bool allowSave,
    required bool allowSearch,
  }) async {
    final data = await _sendJson(
      'PUT',
      '/lab/v1/agents/$agentId/skills/$slug',
      body: {
        'enabled': enabled,
        'override_text': overrideText,
        'allow_save': allowSave,
        'allow_search': allowSearch,
      },
    );
    return LabSkillItem.fromJson(data);
  }
}
