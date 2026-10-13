import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../models/chat_message.dart';
import '../models/chat_conversation.dart';
import 'chat_storage.dart';
import 'chat_context_manager.dart';
import 'chat_context.dart';
import 'web_search_service.dart';

class LLMPerformanceStats {
  final double loadTimeSeconds;
  final double timeToFirstTokenMs;
  final double tokensPerSecond;
  final int totalTokens;
  final double totalGenerationSeconds;
  final double ramUsageMB;
  final double peakRamUsageMB;

  const LLMPerformanceStats({
    this.loadTimeSeconds = 0.0,
    this.timeToFirstTokenMs = 0.0,
    this.tokensPerSecond = 0.0,
    this.totalTokens = 0,
    this.totalGenerationSeconds = 0.0,
    this.ramUsageMB = 0.0,
    this.peakRamUsageMB = 0.0,
  });

  String get summary =>
      '⚡ Скорость: ${tokensPerSecond.toStringAsFixed(1)} tok/s | '
      'Токенов: $totalTokens | '
      'TTFT: ${timeToFirstTokenMs.toStringAsFixed(0)} ms | '
      'RAM: ${ramUsageMB.toStringAsFixed(0)} MB';
}

class LLMService extends ChangeNotifier {
  LlamaBackend? _backend;
  LlamaEngine? _engine;
  ChatSession? _session;
  final ChatStorage _storage;
  final List<ChatConversation> _chats = [];
  late String _activeId;
  Future<void>? _initialization;
  bool _historyReady = false;
  bool _storageWritable = true;
  String? _storageError;
  Timer? _saveTimer;
  int _selectedContextSize = AppConstants.defaultContextSize;
  int _contextSize = AppConstants.defaultContextSize;
  int _contextTokens = 0;
  String _contextStatus = '';
  String? _loadedModelPath;
  bool _isChangingContext = false;

  LLMService({ChatStorage? storage})
    : _storage = storage ?? ChatStorage(getApplicationSupportDirectory) {
    final chat = _newConversation();
    _chats.add(chat);
    _activeId = chat.id;
  }

  static ChatConversation _newConversation() {
    final now = DateTime.now();
    return ChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      updatedAt: now,
    );
  }

  ChatConversation get activeConversation =>
      _chats.firstWhere((c) => c.id == _activeId);
  List<ChatMessage> get _messages => activeConversation.messages;
  List<ChatMessage> get messages => _messages;
  List<ChatConversation> get conversations => List.unmodifiable(
    [..._chats]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );
  bool get historyReady => _historyReady;
  String? get storageError => _storageError;
  int get selectedContextSize => _selectedContextSize;
  int get contextSize => _contextSize;
  int get contextTokens => _contextTokens;
  String get contextStatus => _contextStatus;
  bool get canChangeChat => _historyReady && !_isGenerating && !isLoadingModel;

  Future<void> initializeChats() => _initialization ??= _restoreChats();

  Future<void> _restoreChats() async {
    try {
      final archive = await _storage.load();
      if (_isDisposed) return;
      if (archive != null) {
        _chats
          ..clear()
          ..addAll(archive.conversations);
        _activeId = archive.activeId;
        _selectedContextSize = archive.contextSize;
        _contextSize = archive.contextSize;
      }
    } catch (e) {
      _storageWritable = false;
      debugPrint('[CHAT STORAGE] Restore failed: $e');
      _storageError =
          'Не удалось восстановить чаты. Исходная история сохранена; '
          'новые сообщения пока не записываются на устройство.';
    } finally {
      _historyReady = true;
      notifyListeners();
    }
  }

  void _replaceConversation(ChatConversation chat) {
    final index = _chats.indexWhere((c) => c.id == chat.id);
    _chats[index] = chat;
    _scheduleSave();
  }

  void _addMessage(ChatMessage message) => _replaceConversation(
    activeConversation.withMessages([..._messages, message]),
  );

  void _replaceMessage(int index, ChatMessage message) {
    final messages = [..._messages];
    messages[index] = message;
    _replaceConversation(activeConversation.withMessages(messages));
  }

  void _scheduleSave() {
    if (!_historyReady || !_storageWritable || _saveTimer != null) return;
    _saveTimer = Timer(const Duration(seconds: 1), () {
      _saveTimer = null;
      unawaited(flushChats());
    });
  }

  Future<void> flushChats() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_historyReady || !_storageWritable) return;
    try {
      await _storage.save(
        ChatArchive(
          conversations: [..._chats],
          activeId: _activeId,
          contextSize: _selectedContextSize,
        ),
      );
      if (_storageError != null) {
        _storageError = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CHAT STORAGE] Save failed: $e');
      _storageError =
          'Не удалось сохранить чаты на устройстве. Проверьте свободное место.';
      notifyListeners();
    }
  }

  void createNewChat() {
    if (!canChangeChat) return;
    if (_messages.isEmpty) return;
    final chat = _newConversation();
    _chats.add(chat);
    _activateChat(chat.id);
  }

  void selectChat(String id) {
    if (!canChangeChat || !_chats.any((c) => c.id == id)) return;
    _activateChat(id);
  }

  void _activateChat(String id) {
    _chatEpoch++;
    _activeId = id;
    _session = _engine == null ? null : _createSession();
    _contextTokens = 0;
    _contextStatus = '';
    unawaited(flushChats());
    notifyListeners();
  }

  Future<bool> changeContextSize(int size) async {
    if (!canChangeChat || ![1024, 2048, 4096, 8192].contains(size)) {
      return false;
    }
    if (size == _selectedContextSize) return true;
    _isChangingContext = true;
    notifyListeners();
    try {
      if (_isModelLoaded) {
        final metadata = await _engine!.getMetadata();
        final arch = metadata['general.architecture'];
        final modelLimit = int.tryParse(metadata['$arch.context_length'] ?? '');
        if (modelLimit != null && size > modelLimit) {
          throw StateError(
            'Модель поддерживает контекст до $modelLimit токенов.',
          );
        }
      }
      if (_isDisposed) return false;
      _selectedContextSize = size;
      await flushChats();
      if (_isDisposed) return false;
      if (_isModelLoaded && _loadedModelPath != null) {
        return await _loadModel(
          modelPath: _loadedModelPath!,
          modelDisplayName: _currentModelName,
          contextSize: size,
        );
      }
      _contextSize = size;
      return true;
    } finally {
      _isChangingContext = false;
      notifyListeners();
    }
  }

  String _systemPrompt = AppConstants.defaultSystemPrompt;
  int _chatEpoch = 0;

  bool _isModelLoaded = false;
  bool _isLoadingModel = false;
  bool _isGenerating = false;
  bool _stopRequested = false;
  bool _isDisposed = false;
  String _currentModelName = '';
  String _loadStatus = '';

  // Performance stats
  double _lastTokensPerSecond = 0.0;
  int _lastTokenCount = 0;
  double _lastTtftMs = 0.0;
  double _lastLoadTimeSec = 0.0;
  LLMPerformanceStats _lastStats = const LLMPerformanceStats();

  // Thinking / Reasoning mode
  bool _enableThinking = false;
  bool get enableThinking => _enableThinking;

  void setEnableThinking(bool value) {
    if (_enableThinking != value) {
      _enableThinking = value;
      notifyListeners();
    }
  }

  // Web Search mode
  final WebSearchService _webSearchService = WebSearchService();
  bool _enableWebSearch = true;
  String _searchStatus = '';

  bool get enableWebSearch => _enableWebSearch;
  String get searchStatus => _searchStatus;

  void setEnableWebSearch(bool value) {
    if (_enableWebSearch != value) {
      _enableWebSearch = value;
      notifyListeners();
    }
  }

  int _threads = AppConstants.defaultThreads;
  int get threads => _threads;

  void setThreads(int value) {
    if (_threads != value) {
      _threads = value;
      notifyListeners();
    }
  }

  bool get isModelLoaded => _isModelLoaded;
  bool get isLoadingModel => _isLoadingModel || _isChangingContext;
  bool get isGenerating => _isGenerating;
  String get currentModelName => _currentModelName;
  String get loadStatus => _loadStatus;
  double get lastTokensPerSecond => _lastTokensPerSecond;
  int get lastTokenCount => _lastTokenCount;
  double get lastTtftMs => _lastTtftMs;
  double get lastLoadTimeSec => _lastLoadTimeSec;
  LLMPerformanceStats get lastStats => _lastStats;

  double get currentRamUsageMB {
    try {
      return ProcessInfo.currentRss / (1024 * 1024);
    } catch (_) {
      return 0.0;
    }
  }

  double get peakRamUsageMB {
    try {
      return ProcessInfo.maxRss / (1024 * 1024);
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> initLogging() async {
    try {
      await LlamaLogging.configure(
        level: LlamaLogLevel.info,
        nativeLevel: LlamaLogLevel.info,
        handler: (record) {
          debugPrint('[LLAMA] ${record.level.name}: ${record.message}');
        },
      );
    } catch (e) {
      debugPrint('[LLAMA] Warning: Could not configure logging: $e');
    }
  }

  Future<bool> loadModel({
    required String modelPath,
    required String modelDisplayName,
    int? contextSize,
    int? threads,
  }) {
    if (_isChangingContext || _isDisposed) return Future.value(false);
    return _loadModel(
      modelPath: modelPath,
      modelDisplayName: modelDisplayName,
      contextSize: contextSize,
      threads: threads,
    );
  }

  Future<bool> _loadModel({
    required String modelPath,
    required String modelDisplayName,
    int? contextSize,
    int? threads,
  }) async {
    if (_isLoadingModel || _isGenerating) return false;

    final actualContextSize = contextSize ?? _selectedContextSize;
    final actualThreads = threads ?? _threads;
    _isLoadingModel = true;
    _loadStatus = 'Инициализация движка llama.cpp...';
    notifyListeners();

    final loadStopwatch = Stopwatch()..start();
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[LLM BENCHMARK] Начинается загрузка модели: $modelDisplayName');
    debugPrint('[LLM BENCHMARK] Путь: $modelPath');
    debugPrint(
      '[LLM BENCHMARK] Контекст: $actualContextSize, Потоков: $actualThreads',
    );
    debugPrint(
      '[LLM BENCHMARK] RAM до загрузки: ${currentRamUsageMB.toStringAsFixed(1)} МБ',
    );

    try {
      await initLogging();
      if (_isDisposed) return false;

      if (_engine != null) {
        await _releaseModel();
      }

      _loadStatus = 'Выделение RAM и маппинг тензоров...';
      notifyListeners();

      _backend = LlamaBackend();
      _engine = LlamaEngine(_backend!);

      final modelParams = ModelParams(
        contextSize: actualContextSize,
        numberOfThreads: actualThreads,
        numberOfThreadsBatch: actualThreads,
        useMmap: true,
      );

      // ignore: deprecated_member_use
      await _engine!.loadModel(modelPath, modelParams: modelParams);

      if (_isDisposed) {
        await _releaseModel();
        return false;
      }
      _contextSize = await _engine!.getContextSize();
      if (_contextSize <= 0) _contextSize = actualContextSize;
      _loadedModelPath = modelPath;
      _contextTokens = 0;
      _session = _createSession();
      loadStopwatch.stop();
      _lastLoadTimeSec = loadStopwatch.elapsedMilliseconds / 1000.0;

      _isModelLoaded = true;
      _isLoadingModel = false;
      _currentModelName = modelDisplayName;
      _loadStatus =
          'Модель готова за ${_lastLoadTimeSec.toStringAsFixed(2)} сек '
          '(RAM: ${currentRamUsageMB.toStringAsFixed(0)} МБ)';

      debugPrint(
        '[LLM BENCHMARK] Модель успешно загружена за: ${_lastLoadTimeSec.toStringAsFixed(2)} сек',
      );
      debugPrint(
        '[LLM BENCHMARK] RAM после загрузки: ${currentRamUsageMB.toStringAsFixed(1)} МБ (Пик: ${peakRamUsageMB.toStringAsFixed(1)} МБ)',
      );
      debugPrint('═══════════════════════════════════════════════════════════');

      notifyListeners();
      return true;
    } catch (e, stack) {
      loadStopwatch.stop();
      _isModelLoaded = false;
      _isLoadingModel = false;
      await _releaseModel();
      _loadStatus = 'Ошибка загрузки: $e';
      debugPrint('[LLM BENCHMARK] ❌ Ошибка загрузки модели: $e');
      debugPrint('[LLM BENCHMARK] Stacktrace: $stack');
      notifyListeners();
      return false;
    }
  }

  Stream<void> generateResponseStream({
    required String userPrompt,
    String systemPrompt = AppConstants.defaultSystemPrompt,
    double temperature = AppConstants.defaultTemperature,
    double topP = AppConstants.defaultTopP,
  }) async* {
    await initializeChats();
    if (!_isModelLoaded || _session == null) {
      throw Exception('Модель не загружена');
    }

    if (_isGenerating || isLoadingModel || _isDisposed) {
      throw StateError('Генерация уже выполняется или модель загружается');
    }
    final epoch = _chatEpoch;
    _systemPrompt = systemPrompt;
    _session = _createSession();

    final now = DateTime.now();
    final userId = '${now.microsecondsSinceEpoch}-user';
    final replyId = '${now.microsecondsSinceEpoch}-assistant';
    _addMessage(
      ChatMessage(id: userId, text: userPrompt, isUser: true, timestamp: now),
    );
    _addMessage(
      ChatMessage(
        id: replyId,
        text: '',
        isUser: false,
        timestamp: now,
        isGenerating: true,
      ),
    );
    final answer = StringBuffer();
    final reasoning = StringBuffer();
    _stopRequested = false;
    _isGenerating = true;
    _lastTokensPerSecond = 0.0;
    _lastTokenCount = 0;
    _lastTtftMs = 0.0;
    notifyListeners();

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[LLM BENCHMARK] Запуск инференса для промпта: "$userPrompt"');
    debugPrint('[LLM BENCHMARK] Температура: $temperature, topP: $topP');

    final stopwatch = Stopwatch()..start();
    int generatedTokens = 0;
    bool isFirstToken = true;

    try {
      String effectivePrompt = userPrompt;
      if (_enableWebSearch) {
        _searchStatus = 'Поиск в интернете...';
        notifyListeners();
        try {
          final webContext = await _webSearchService.getWebContext(userPrompt);
          if (webContext != null && webContext.isNotEmpty) {
            debugPrint(
              '[WEB SEARCH] Данные из интернета получены:\n$webContext',
            );
            effectivePrompt =
                '$webContext\n\n'
                'ВАЖНО: Используй вышеприведенные актуальные данные из интернета, чтобы точно ответить на вопрос пользователя. '
                'Отвечай обязательно на том же языке, на котором задан вопрос (казахский/русский/английский):\n'
                '$userPrompt';
          }
        } catch (e) {
          debugPrint('[WEB SEARCH] Ошибка веб-поиска: $e');
        } finally {
          _searchStatus = '';
          notifyListeners();
        }
      }

      if (_stopRequested || epoch != _chatEpoch) return;
      final userIndex = _messages.indexWhere((m) => m.id == userId);
      if (userIndex != -1) {
        _replaceMessage(
          userIndex,
          _messages[userIndex].copyWith(contextText: effectivePrompt),
        );
      }
      final promptParts = [LlamaTextContent(effectivePrompt)];

      _contextStatus = 'Подготовка контекста…';
      notifyListeners();
      final prepared = await ChatContextManager(_engine!).prepare(
        conversation: activeConversation,
        systemPrompt: _systemPrompt,
        userPrompt: effectivePrompt,
        contextSize: _contextSize,
        thinking: _enableThinking,
        cancelled: () => _stopRequested || epoch != _chatEpoch || _isDisposed,
        onStatus: (status) {
          _contextStatus = status;
          notifyListeners();
        },
        onSummary: (summary, throughId) {
          _replaceConversation(
            activeConversation.withSummary(summary, throughId),
          );
        },
      );
      if (_stopRequested || epoch != _chatEpoch) return;
      _contextTokens = prepared.promptTokens;
      _contextStatus = '';
      _session = _createSession();
      final session = _session!;
      final generationParams = GenerationParams(
        temp: temperature,
        topP: topP,
        maxTokens: prepared.responseTokens,
      );
      notifyListeners();

      final stream = session.create(
        promptParts,
        params: generationParams,
        enableThinking: _enableThinking,
      );

      await for (final chunk in stream) {
        if (_stopRequested || epoch != _chatEpoch) {
          debugPrint('[LLM BENCHMARK] Генерация прервана пользователем.');
          break;
        }

        final text = chunk.text;
        final thought = chunk.thinking;
        if (text.isNotEmpty || thought.isNotEmpty) {
          if (isFirstToken) {
            _lastTtftMs = stopwatch.elapsedMilliseconds.toDouble();
            isFirstToken = false;
            debugPrint(
              '[LLM BENCHMARK] ⏱️ TTFT (время до первого токена): ${_lastTtftMs.toStringAsFixed(0)} мс',
            );
          }

          generatedTokens++;
          _lastTokenCount = generatedTokens;

          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          if (elapsedSec > 0) {
            _lastTokensPerSecond = generatedTokens / elapsedSec;
          }

          answer.write(text);
          reasoning.write(thought);
          _updateReply(
            replyId,
            text: answer.toString(),
            reasoning: reasoning.toString(),
          );
          notifyListeners();
          yield null;
        }
      }
    } catch (e, stack) {
      debugPrint('[LLM BENCHMARK] ❌ Ошибка инференса: $e');
      debugPrint('[LLM BENCHMARK] Stack: $stack');
      if (epoch == _chatEpoch &&
          !_stopRequested &&
          e is! ContextPreparationCancelled) {
        _updateReply(replyId, error: e.toString());
      }
    } finally {
      stopwatch.stop();
      _isGenerating = false;
      _contextStatus = '';
      if (epoch == _chatEpoch) {
        _updateReply(replyId, isGenerating: false);
      }
      final totalSec = stopwatch.elapsedMilliseconds / 1000.0;
      final finalSpeed = totalSec > 0 ? (generatedTokens / totalSec) : 0.0;

      _lastStats = LLMPerformanceStats(
        loadTimeSeconds: _lastLoadTimeSec,
        timeToFirstTokenMs: _lastTtftMs,
        tokensPerSecond: finalSpeed,
        totalTokens: generatedTokens,
        totalGenerationSeconds: totalSec,
        ramUsageMB: currentRamUsageMB,
        peakRamUsageMB: peakRamUsageMB,
      );

      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('[LLM BENCHMARK РЕЗУЛЬТАТЫ]:');
      debugPrint('  • Сгенерировано токенов: $generatedTokens');
      debugPrint('  • Время генерации: ${totalSec.toStringAsFixed(2)} сек');
      debugPrint('  • Скорость: ${finalSpeed.toStringAsFixed(2)} токенов/сек');
      debugPrint('  • TTFT: ${_lastTtftMs.toStringAsFixed(0)} мс');
      debugPrint('  • RAM текущая: ${currentRamUsageMB.toStringAsFixed(1)} МБ');
      debugPrint('  • RAM пиковая: ${peakRamUsageMB.toStringAsFixed(1)} МБ');
      debugPrint('═══════════════════════════════════════════════════════════');

      notifyListeners();
      await flushChats();
      if (_isDisposed) await unloadModel();
    }
  }

  void stopGeneration() {
    if (_isGenerating && _engine != null) {
      try {
        _stopRequested = true;
        _engine!.cancelGeneration();
      } catch (e) {
        debugPrint('[LLM] Error canceling generation: $e');
      }
      notifyListeners();
    }
  }

  ChatSession _createSession() => createChatSession(
    _engine!,
    _messages,
    systemPrompt: _systemPrompt,
    summary: activeConversation.summary,
    summarizedThroughId: activeConversation.summarizedThroughId,
  );

  void _updateReply(
    String id, {
    String? text,
    String? reasoning,
    String? error,
    bool? isGenerating,
  }) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _replaceMessage(
      index,
      _messages[index].copyWith(
        text: text,
        reasoning: reasoning,
        error: error,
        isGenerating: isGenerating,
        tokensPerSecond: _lastTokensPerSecond,
        totalTokens: _lastTokenCount,
      ),
    );
  }

  void resetChatSession() {
    _chatEpoch++;
    stopGeneration();
    _replaceConversation(
      activeConversation.withMessages([], clearSummary: true),
    );
    _contextTokens = 0;
    _contextStatus = '';
    unawaited(flushChats());
    _session?.reset();
    notifyListeners();
  }

  Future<void> unloadModel() async {
    if (_isGenerating || isLoadingModel) return;
    await _releaseModel();
  }

  Future<void> _releaseModel() async {
    try {
      if (_engine != null) {
        await _engine!.unloadModel();
        await _engine!.dispose();
        _engine = null;
      }
      _backend = null;
      _session = null;
      _isModelLoaded = false;
      _currentModelName = '';
      _loadStatus = 'Модель выгружена из памяти';
      notifyListeners();
    } catch (e) {
      debugPrint('[LLM] Error unloading model: $e');
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    stopGeneration();
    unawaited(flushChats());
    _isDisposed = true;
    if (!_isGenerating && !_isLoadingModel) unawaited(_releaseModel());
    super.dispose();
  }
}
