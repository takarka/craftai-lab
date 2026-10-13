import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import '../core/constants/app_constants.dart';

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

  bool _isModelLoaded = false;
  bool _isLoadingModel = false;
  bool _isGenerating = false;
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

  bool get isModelLoaded => _isModelLoaded;
  bool get isLoadingModel => _isLoadingModel;
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
    int contextSize = AppConstants.defaultContextSize,
    int threads = AppConstants.defaultThreads,
  }) async {
    if (_isLoadingModel) return false;

    _isLoadingModel = true;
    _loadStatus = 'Инициализация движка llama.cpp...';
    notifyListeners();

    final loadStopwatch = Stopwatch()..start();
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[LLM BENCHMARK] Начинается загрузка модели: $modelDisplayName');
    debugPrint('[LLM BENCHMARK] Путь: $modelPath');
    debugPrint('[LLM BENCHMARK] Контекст: $contextSize, Потоков: $threads');
    debugPrint('[LLM BENCHMARK] RAM до загрузки: ${currentRamUsageMB.toStringAsFixed(1)} МБ');

    try {
      await initLogging();

      if (_engine != null) {
        await unloadModel();
      }

      _loadStatus = 'Выделение RAM и маппинг тензоров...';
      notifyListeners();

      _backend = LlamaBackend();
      _engine = LlamaEngine(_backend!);

      final modelParams = ModelParams(
        contextSize: contextSize,
        numberOfThreads: threads,
        numberOfThreadsBatch: threads,
        useMmap: true,
      );

      // ignore: deprecated_member_use
      await _engine!.loadModel(
        modelPath,
        modelParams: modelParams,
      );

      _session = ChatSession(_engine!);
      loadStopwatch.stop();
      _lastLoadTimeSec = loadStopwatch.elapsedMilliseconds / 1000.0;

      _isModelLoaded = true;
      _isLoadingModel = false;
      _currentModelName = modelDisplayName;
      _loadStatus = 'Модель готова за ${_lastLoadTimeSec.toStringAsFixed(2)} сек '
          '(RAM: ${currentRamUsageMB.toStringAsFixed(0)} МБ)';

      debugPrint('[LLM BENCHMARK] Модель успешно загружена за: ${_lastLoadTimeSec.toStringAsFixed(2)} сек');
      debugPrint('[LLM BENCHMARK] RAM после загрузки: ${currentRamUsageMB.toStringAsFixed(1)} МБ (Пик: ${peakRamUsageMB.toStringAsFixed(1)} МБ)');
      debugPrint('═══════════════════════════════════════════════════════════');

      notifyListeners();
      return true;
    } catch (e, stack) {
      loadStopwatch.stop();
      _isModelLoaded = false;
      _isLoadingModel = false;
      _loadStatus = 'Ошибка загрузки: $e';
      debugPrint('[LLM BENCHMARK] ❌ Ошибка загрузки модели: $e');
      debugPrint('[LLM BENCHMARK] Stacktrace: $stack');
      notifyListeners();
      return false;
    }
  }

  Stream<String> generateResponseStream({
    required String userPrompt,
    String systemPrompt = AppConstants.defaultSystemPrompt,
    double temperature = AppConstants.defaultTemperature,
    double topP = AppConstants.defaultTopP,
  }) async* {
    if (!_isModelLoaded || _session == null) {
      throw Exception('Модель не загружена');
    }

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
      final promptParts = [
        LlamaTextContent(userPrompt),
      ];

      final generationParams = GenerationParams(
        temp: temperature,
        topP: topP,
      );

      final stream = _session!.create(
        promptParts,
        params: generationParams,
        enableThinking: _enableThinking,
      );

      await for (final chunk in stream) {
        if (!_isGenerating) {
          debugPrint('[LLM BENCHMARK] Генерация прервана пользователем.');
          break;
        }

        final text = chunk.text;
        if (text.isNotEmpty) {
          if (isFirstToken) {
            _lastTtftMs = stopwatch.elapsedMilliseconds.toDouble();
            isFirstToken = false;
            debugPrint('[LLM BENCHMARK] ⏱️ TTFT (время до первого токена): ${_lastTtftMs.toStringAsFixed(0)} мс');
          }

          generatedTokens++;
          _lastTokenCount = generatedTokens;

          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          if (elapsedSec > 0) {
            _lastTokensPerSecond = generatedTokens / elapsedSec;
          }

          yield text;
        }
      }
    } catch (e, stack) {
      debugPrint('[LLM BENCHMARK] ❌ Ошибка инференса: $e');
      debugPrint('[LLM BENCHMARK] Stack: $stack');
      rethrow;
    } finally {
      stopwatch.stop();
      _isGenerating = false;
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
    }
  }

  void stopGeneration() {
    if (_isGenerating && _engine != null) {
      try {
        _isGenerating = false;
        _engine!.cancelGeneration();
      } catch (e) {
        debugPrint('[LLM] Error canceling generation: $e');
      }
      notifyListeners();
    }
  }

  void resetChatSession() {
    if (_engine != null && _isModelLoaded) {
      _session = ChatSession(_engine!);
      notifyListeners();
    }
  }

  Future<void> unloadModel() async {
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
  void dispose() {
    unloadModel();
    super.dispose();
  }
}
