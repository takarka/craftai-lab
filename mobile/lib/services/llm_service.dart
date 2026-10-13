import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import '../core/constants/app_constants.dart';

class LLMService extends ChangeNotifier {
  LlamaBackend? _backend;
  LlamaEngine? _engine;
  ChatSession? _session;

  bool _isModelLoaded = false;
  bool _isLoadingModel = false;
  bool _isGenerating = false;
  String _currentModelName = '';
  String _loadStatus = '';

  // Stats
  double _lastTokensPerSecond = 0.0;
  int _lastTokenCount = 0;

  bool get isModelLoaded => _isModelLoaded;
  bool get isLoadingModel => _isLoadingModel;
  bool get isGenerating => _isGenerating;
  String get currentModelName => _currentModelName;
  String get loadStatus => _loadStatus;
  double get lastTokensPerSecond => _lastTokensPerSecond;
  int get lastTokenCount => _lastTokenCount;

  Future<bool> loadModel({
    required String modelPath,
    required String modelDisplayName,
    int contextSize = AppConstants.defaultContextSize,
    int threads = AppConstants.defaultThreads,
  }) async {
    if (_isLoadingModel) return false;

    _isLoadingModel = true;
    _loadStatus = 'Инициализация движка...';
    notifyListeners();

    try {
      if (_engine != null) {
        await unloadModel();
      }

      _loadStatus = 'Выделение памяти и загрузка весов...';
      notifyListeners();

      _backend = LlamaBackend();
      _engine = LlamaEngine(_backend!);

      final modelParams = ModelParams(
        contextSize: contextSize,
        numberOfThreads: threads,
        numberOfThreadsBatch: threads,
      );

      // ignore: deprecated_member_use
      await _engine!.loadModel(
        modelPath,
        modelParams: modelParams,
      );

      _session = ChatSession(_engine!);
      _isModelLoaded = true;
      _isLoadingModel = false;
      _currentModelName = modelDisplayName;
      _loadStatus = 'Модель готова к работе';
      notifyListeners();
      return true;
    } catch (e) {
      _isModelLoaded = false;
      _isLoadingModel = false;
      _loadStatus = 'Ошибка загрузки: $e';
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
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    int generatedTokens = 0;

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
      );

      await for (final chunk in stream) {
        if (!_isGenerating) {
          break;
        }

        final text = chunk.text;
        if (text.isNotEmpty) {
          generatedTokens++;
          _lastTokenCount = generatedTokens;

          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          if (elapsedSec > 0) {
            _lastTokensPerSecond = generatedTokens / elapsedSec;
          }

          yield text;
        }
      }
    } catch (e) {
      debugPrint('Error during generation: $e');
      rethrow;
    } finally {
      stopwatch.stop();
      _isGenerating = false;
      notifyListeners();
    }
  }

  void stopGeneration() {
    if (_isGenerating && _engine != null) {
      try {
        _isGenerating = false;
        _engine!.cancelGeneration();
      } catch (e) {
        debugPrint('Error canceling generation: $e');
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
      _loadStatus = 'Модель выгружена';
      notifyListeners();
    } catch (e) {
      debugPrint('Error unloading model: $e');
    }
  }

  @override
  void dispose() {
    unloadModel();
    super.dispose();
  }
}
