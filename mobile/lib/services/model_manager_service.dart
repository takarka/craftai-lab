import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LocalModelFile {
  final String path;
  final String name;
  final int sizeBytes;

  LocalModelFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} КБ';
    } else if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    } else {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    }
  }
}

class ModelManagerService extends ChangeNotifier {
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';
  List<LocalModelFile> _localModels = [];

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get downloadStatusText => _downloadStatusText;
  List<LocalModelFile> get localModels => _localModels;

  Future<String> getModelsDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${docsDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  Future<void> refreshLocalModels() async {
    try {
      final modelsDirPath = await getModelsDirectory();
      final dir = Directory(modelsDirPath);
      final files = await dir.list().toList();

      final List<LocalModelFile> result = [];
      for (final entity in files) {
        if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
          final stat = await entity.stat();
          final name = entity.uri.pathSegments.last;
          result.add(
            LocalModelFile(
              path: entity.path,
              name: name,
              sizeBytes: stat.size,
            ),
          );
        }
      }
      _localModels = result;
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing local models: $e');
    }
  }

  Future<String?> downloadModel({
    required String url,
    required String targetFileName,
  }) async {
    if (_isDownloading) return null;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _downloadStatusText = 'Подготовка к загрузке...';
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final modelsDir = await getModelsDirectory();
      final savePath = '$modelsDir/$targetFileName';
      final tempPath = '$savePath.download';

      int lastReceived = 0;
      DateTime lastTime = DateTime.now();

      await _dio.download(
        url,
        tempPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _downloadProgress = received / total;
            final now = DateTime.now();
            final elapsedSec = now.difference(lastTime).inMilliseconds / 1000.0;
            if (elapsedSec >= 0.5) {
              final bytesDiff = received - lastReceived;
              final speedMBs = (bytesDiff / (1024 * 1024)) / elapsedSec;
              final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
              final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
              final percent = (_downloadProgress * 100).toStringAsFixed(1);

              _downloadStatusText =
                  '$percent% ($receivedMB / $totalMB МБ) • ${speedMBs.toStringAsFixed(1)} МБ/с';
              lastReceived = received;
              lastTime = now;
              notifyListeners();
            }
          }
        },
      );

      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        final finalFile = File(savePath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await tempFile.rename(savePath);
      }

      _isDownloading = false;
      _downloadProgress = 1.0;
      _downloadStatusText = 'Загрузка завершена!';
      await refreshLocalModels();
      notifyListeners();
      return savePath;
    } catch (e) {
      _isDownloading = false;
      _downloadStatusText = 'Ошибка загрузки: $e';
      notifyListeners();
      return null;
    }
  }

  void cancelDownload() {
    if (_isDownloading && _cancelToken != null) {
      _cancelToken!.cancel('Отменено пользователем');
      _isDownloading = false;
      _downloadStatusText = 'Загрузка отменена';
      notifyListeners();
    }
  }

  Future<String?> pickLocalModelFile() async {
    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.any,
      );

      if (pickedFile != null && pickedFile.path != null) {
        final sourcePath = pickedFile.path!;
        if (!sourcePath.toLowerCase().endsWith('.gguf')) {
          _downloadStatusText = 'Выбранный файл должен иметь расширение .gguf';
          notifyListeners();
          return null;
        }

        final fileName = pickedFile.name;
        final modelsDir = await getModelsDirectory();
        final destPath = '$modelsDir/$fileName';

        final sourceFile = File(sourcePath);
        final destFile = File(destPath);

        // If source is already in modelsDir, just return it
        if (sourceFile.path == destFile.path) {
          await refreshLocalModels();
          return destPath;
        }

        _downloadStatusText = 'Импорт модели в хранилище приложения...';
        notifyListeners();

        await sourceFile.copy(destPath);
        await refreshLocalModels();
        _downloadStatusText = 'Модель успешно импортирована!';
        notifyListeners();
        return destPath;
      }
    } catch (e) {
      _downloadStatusText = 'Ошибка выбора файла: $e';
      notifyListeners();
    }
    return null;
  }

  Future<void> deleteModel(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        await refreshLocalModels();
      }
    } catch (e) {
      debugPrint('Error deleting model: $e');
    }
  }
}
