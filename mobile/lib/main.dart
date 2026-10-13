import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'services/llm_service.dart';
import 'services/model_manager_service.dart';
import 'ui/screens/chat_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QwenChatApp());
}

class QwenChatApp extends StatefulWidget {
  const QwenChatApp({super.key});

  @override
  State<QwenChatApp> createState() => _QwenChatAppState();
}

class _QwenChatAppState extends State<QwenChatApp> with WidgetsBindingObserver {
  late final ModelManagerService _modelManager;
  late final LLMService _llmService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _modelManager = ModelManagerService();
    _llmService = LLMService();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _llmService.initializeChats();
    if (!mounted) return;
    await _modelManager.refreshLocalModels();
    if (!mounted) return;
    // If a local GGUF model already exists, auto-load the first one
    if (_modelManager.localModels.isNotEmpty) {
      final firstModel = _modelManager.localModels.first;
      _llmService.loadModel(
        modelPath: firstModel.path,
        modelDisplayName: firstModel.name,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _llmService.flushChats();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _llmService.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: ChatScreen(llmService: _llmService, modelManager: _modelManager),
    );
  }
}
