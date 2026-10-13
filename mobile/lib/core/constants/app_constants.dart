class AppConstants {
  static const String appTitle = 'Local AI Chat';

  // System Prompt for Qwen & Gemma
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
    // --- Qwen Family ---
    {
      'family': 'Qwen',
      'name': 'Qwen 2.5 (1.5B) Instruct Q4_K_M',
      'fileName': 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'size': '~1.1 ГБ',
      'description': 'Оптимальный баланс ума и скорости для Snapdragon 720G',
    },
    {
      'family': 'Qwen',
      'name': 'Qwen 2.5 (0.5B) Instruct Q4_K_M',
      'fileName': 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'size': '~398 МБ',
      'description': 'Ультрабыстрая и компактная модель, мгновенные ответы (15-20 tok/s)',
    },
    {
      'family': 'Qwen',
      'name': 'Qwen 2.5 (3B) Instruct Q4_K_M',
      'fileName': 'qwen2.5-3b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
      'size': '~2.2 ГБ',
      'description': 'Максимальное качество рассуждений (требует ~3 ГБ RAM)',
    },

    // --- Google Gemma Family ---
    {
      'family': 'Gemma',
      'name': 'Google Gemma 2 (2B) Instruct Q4_K_M',
      'fileName': 'gemma-2-2b-it-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      'size': '~1.6 ГБ',
      'description': 'Флагманская компактная модель от Google DeepMind с высокой точностью ответов',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 2 (2B) Instruct Q4_0',
      'fileName': 'gemma-2-2b-it-Q4_0.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_0.gguf',
      'size': '~1.5 ГБ',
      'description': 'Оптимизированное квантование Q4_0 для максимальной скорости на мобильном CPU',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 1.1 (2B) Instruct Q4_K_M',
      'fileName': 'gemma-1.1-2b-it-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-1.1-2b-it-GGUF/resolve/main/gemma-1.1-2b-it-Q4_K_M.gguf',
      'size': '~1.5 ГБ',
      'description': 'Классическая легкая модель Gemma первого поколения от Google',
    },
  ];
}
