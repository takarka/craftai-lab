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
      'params': '1.5B',
      'badge': 'Баланс',
      'fileName': 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'url': 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'size': '~1.1 ГБ',
      'description': 'Оптимальный баланс ума и скорости для Snapdragon 720G',
    },
    {
      'family': 'Qwen',
      'name': 'Qwen 2.5 (0.5B) Instruct Q4_K_M',
      'params': '0.5B',
      'badge': 'Ультрабыстрая',
      'fileName': 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'url': 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'size': '~398 МБ',
      'description':
          'Ультрабыстрая и компактная модель, мгновенные ответы (15-20 tok/s)',
    },
    {
      'family': 'Qwen',
      'name': 'Qwen 2.5 (3B) Instruct Q4_K_M',
      'params': '3B',
      'badge': 'Интеллект',
      'fileName': 'qwen2.5-3b-instruct-q4_k_m.gguf',
      'url': 'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
      'size': '~2.2 ГБ',
      'description': 'Максимальное качество рассуждений (требует ~3 ГБ RAM)',
    },

    // --- Google Gemma / Gemini Family ---
    {
      'family': 'Gemma',
      'name': 'Google Gemma 3 (1B) Instruct Q4_K_M',
      'params': '1.0B (Gemma 3)',
      'badge': 'Рекомендуемая',
      'fileName': 'gemma-3-1b-it-Q4_K_M.gguf',
      'url': 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf',
      'size': '~806 МБ',
      'description': 'Новейшая модель Gemma 3 от Google DeepMind с архитектурой Gemini. Мгновенный запуск и минимальное потребление RAM (~1.2 ГБ).',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 3 (1B) Instruct Q8_0',
      'params': '1.0B (Gemma 3)',
      'badge': 'Макс. точность',
      'fileName': 'gemma-3-1b-it-Q8_0.gguf',
      'url': 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q8_0.gguf',
      'size': '~1.07 ГБ',
      'description': '8-битная версия Gemma 3 без потери качества. Безупречное следование инструкциям и логика для 1B модели.',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 3 (4B) Instruct Q4_K_M',
      'params': '4.0B (Gemma 3)',
      'badge': 'Флагман 4B',
      'fileName': 'gemma-3-4b-it-Q4_K_M.gguf',
      'url': 'https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf',
      'size': '~2.49 ГБ',
      'description': 'Мощный флагман нового поколения с сильными способностями к рассуждению и диалогам уровня Gemini (~3.2 ГБ RAM).',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 3 (4B) Instruct Q3_K_M',
      'params': '4.0B (Gemma 3)',
      'badge': 'Быстрая 4B',
      'fileName': 'gemma-3-4b-it-Q3_K_M.gguf',
      'url': 'https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q3_K_M.gguf',
      'size': '~2.1 ГБ',
      'description': 'Облегченная 4B модель Gemma 3: высокая сообразительность при экономии оперативной памяти устройства (~2.6 ГБ RAM).',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 2 (2B) Instruct Q4_K_M',
      'params': '2.6B',
      'badge': 'Баланс',
      'fileName': 'gemma-2-2b-it-Q4_K_M.gguf',
      'url': 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      'size': '~1.6 ГБ',
      'description': 'Проверенная временем стабильная модель Google DeepMind с отличным качеством русского языка.',
    },
    {
      'family': 'Gemma',
      'name': 'Google CodeGemma (2B) Q4_K_M',
      'params': '2.5B (Код)',
      'badge': 'Программирование',
      'fileName': 'codegemma-2b-Q4_K_M.gguf',
      'url': 'https://huggingface.co/bartowski/codegemma-2b-GGUF/resolve/main/codegemma-2b-Q4_K_M.gguf',
      'size': '~1.63 ГБ',
      'description': 'Специализированная модель Google для анализа кода, поиска ошибок и помощи в программировании.',
    },
  ];
}
