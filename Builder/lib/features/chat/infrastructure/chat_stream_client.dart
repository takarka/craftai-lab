import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/infrastructure/craft_ai_client.dart';
import '../../session/domain/auth_tokens.dart';
import '../../session/infrastructure/secure_token_storage.dart';
import '../domain/chat_stream_event.dart';

class ChatCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

class ChatStreamClient {
  static const String defaultBaseUrl = 'https://localhost:5001';

  final String baseUrl;
  final SecureTokenStorage tokenStorage;
  final http.Client _client;

  ChatStreamClient({
    this.baseUrl = defaultBaseUrl,
    required this.tokenStorage,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Stream<StreamEvent> streamCompletion({
    required String ownerId,
    required String category,
    required String catalogRevision,
    required List<Map<String, String>> messages,
    List<Map<String, dynamic>> tools = const [],
    int toolStep = 0,
    String? requestId,
    ChatCancellationToken? cancellationToken,
  }) async* {
    final activeRequestId = requestId ?? CraftAiClient.generateRequestId();

    AuthTokens? session;
    try {
      session = await tokenStorage.readTokens();
    } catch (_) {}

    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw const CraftAiAuthException(
        'Требуется авторизация для отправки сообщения.',
      );
    }

    final uri = Uri.parse('$baseUrl/builder/chat/completions');
    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['X-Request-Id'] = activeRequestId;

    final bodyJson = {
      'category': category,
      'catalogRevision': catalogRevision,
      'messages': messages,
      'tools': tools,
      'toolStep': toolStep,
    };
    request.body = jsonEncode(bodyJson);

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on SocketException catch (e) {
      throw CraftAiNetworkException(
        'Нет подключения к сети. Проверьте интернет: ${e.message}',
      );
    } on http.ClientException catch (e) {
      throw CraftAiNetworkException(
        'Сетевая ошибка при обращении к серверу: ${e.message}',
      );
    } catch (e) {
      throw CraftAiNetworkException('Не удалось отправить запрос: $e');
    }

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      String message = 'Ошибка сервера (${response.statusCode})';
      String code = 'SERVER_ERROR';

      try {
        final parsed = jsonDecode(errorBody) as Map<String, dynamic>;
        if (parsed.containsKey('message')) {
          message = parsed['message'].toString();
        }
        if (parsed.containsKey('code')) {
          code = parsed['code'].toString();
        }
      } catch (_) {}

      if (response.statusCode == 401) {
        throw CraftAiAuthException(message);
      } else if (response.statusCode == 403) {
        throw CraftAiForbiddenException(message);
      } else if (response.statusCode == 503 || code == 'MODEL_UNAVAILABLE') {
        throw CraftAiServerException(message, statusCode: 503);
      } else {
        throw CraftAiServerException(message, statusCode: response.statusCode);
      }
    }

    // Parse SSE stream
    String lineBuffer = '';
    final List<String> currentDataLines = [];

    StreamSubscription<List<int>>? subscription;
    final controller = StreamController<StreamEvent>();

    void closeSub() {
      subscription?.cancel();
      subscription = null;
    }

    cancellationToken?.addListener(() {
      closeSub();
      if (!controller.isClosed) {
        controller.add(
          TerminalStreamEvent(
            requestId: activeRequestId,
            sequence: 9999,
            eventId: 'cancelled',
            state: 'interrupted',
          ),
        );
        controller.close();
      }
    });

    subscription = response.stream.listen(
      (bytes) {
        final chunk = utf8.decode(bytes, allowMalformed: true);
        lineBuffer += chunk;

        final lines = lineBuffer.split('\n');
        lineBuffer = lines.removeLast(); // keep unfinished line in buffer

        for (final rawLine in lines) {
          final line = rawLine.trimRight();
          if (line.isEmpty) {
            // End of SSE message block
            if (currentDataLines.isNotEmpty) {
              final rawData = currentDataLines.join('\n');
              try {
                final json = jsonDecode(rawData) as Map<String, dynamic>;
                final event = StreamEvent.fromJson(json);
                if (!controller.isClosed) {
                  controller.add(event);
                }
              } catch (_) {}
            }
            currentDataLines.clear();
          } else if (line.startsWith('data:')) {
            currentDataLines.add(line.substring(5).trim());
          }
        }
      },
      onError: (err) {
        if (!controller.isClosed) {
          controller.addError(
            CraftAiNetworkException('Разрыв потока данных: $err'),
          );
          controller.close();
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
      },
      cancelOnError: true,
    );

    yield* controller.stream;
  }
}
