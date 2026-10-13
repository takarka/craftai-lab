class AppConstants {
  static const String appTitle = 'Qwen AI Chat';

  // System Prompt for Qwen
  static const String defaultSystemPrompt =
      'Ты полезный, умный и дружелюбный ИИ-помощник. '
      'Отвечай четко, грамотно и по делу.';

  // Default inference parameters
  static const int defaultContextSize = 2048;
  static const int defaultThreads = 4;
  static const double defaultTemperature = 0.7;
  static const double defaultTopP = 0.8;
  static const int defaultMaxTokens = 1024;

  // Preset models available for one-tap download
  static const List<Map<String, String>> presetModels = [
    {
      'name': 'Qwen 2.5 (1.5B) Instruct Q4_K_M',
      'fileName': 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'size': '~1.1 ГБ',
      'description': 'Оптимальный баланс ума и скорости для Snapdragon 720G',
    },
    {
      'name': 'Qwen 2.5 (0.5B) Instruct Q4_K_M',
      'fileName': 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'size': '~398 МБ',
      'description': 'Ультрабыстрая и компактная модель, мгновенные ответы',
    },
    {
      'name': 'Qwen 2.5 (3B) Instruct Q4_K_M',
      'fileName': 'qwen2.5-3b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
      'size': '~2.2 ГБ',
      'description': 'Максимальное качество рассуждений (требует ~3 ГБ RAM)',
    },
  ];
}
