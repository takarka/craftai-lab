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
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'size': '~1.1 ГБ',
      'description': 'Оптимальный баланс ума и скорости для Snapdragon 720G',
    },
    {
      'family': 'Qwen',
      'name': 'Qwen 2.5 (0.5B) Instruct Q4_K_M',
      'params': '0.5B',
      'badge': 'Ультрабыстрая',
      'fileName': 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'size': '~398 МБ',
      'description': 'Ультрабыстрая и компактная модель, мгновенные ответы (15-20 tok/s)',
    },
    {
      'family': 'Qwen',
      'name': 'Qwen 2.5 (3B) Instruct Q4_K_M',
      'params': '3B',
      'badge': 'Интеллект',
      'fileName': 'qwen2.5-3b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
      'size': '~2.2 ГБ',
      'description': 'Максимальное качество рассуждений (требует ~3 ГБ RAM)',
    },

    // --- Google Gemma Family (2B, 7B, 9B + Code) ---
    {
      'family': 'Gemma',
      'name': 'Google Gemma 2 (2B) Instruct Q4_K_M',
      'params': '2.6B',
      'badge': 'Баланс',
      'fileName': 'gemma-2-2b-it-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      'size': '~1.6 ГБ',
      'description': 'Флагманская компактная модель от Google DeepMind. Отличная логика и знание языков.',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 2 (2B) Instruct IQ3_M',
      'params': '2.6B',
      'badge': 'Быстрая',
      'fileName': 'gemma-2-2b-it-IQ3_M.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-IQ3_M.gguf',
      'size': '~1.27 ГБ',
      'description': 'Облегченная версия Gemma 2: экономит RAM и выдает более высокий темп токенов/сек.',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 2 (2B) Instruct Q6_K',
      'params': '2.6B',
      'badge': 'Макс. точность',
      'fileName': 'gemma-2-2b-it-Q6_K.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q6_K.gguf',
      'size': '~2.1 ГБ',
      'description': '6-битное высокоточное квантование. Качество ответов практически не уступает FP16.',
    },
    {
      'family': 'Gemma',
      'name': 'Google CodeGemma (2B) Q4_K_M',
      'params': '2.5B (Код)',
      'badge': 'Программирование',
      'fileName': 'codegemma-2b-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/codegemma-2b-GGUF/resolve/main/codegemma-2b-Q4_K_M.gguf',
      'size': '~1.63 ГБ',
      'description': 'Специализированная модель Google для написания, анализа и автодополнения кода.',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 2 (9B) Instruct Q2_K',
      'params': '9.2B (Флагман)',
      'badge': 'Тяжелая 9B',
      'fileName': 'gemma-2-9b-it-Q2_K.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-9b-it-GGUF/resolve/main/gemma-2-9b-it-Q2_K.gguf',
      'size': '~3.81 ГБ',
      'description': 'Старшая 9-миллиардная флагманская модель DeepMind. Глубокий интеллект (требует ~4.2 ГБ RAM).',
    },
    {
      'family': 'Gemma',
      'name': 'Google CodeGemma 1.1 (7B) Instruct Q3_K_M',
      'params': '7.0B (Код)',
      'badge': 'Senior Dev',
      'fileName': 'codegemma-1.1-7b-it-Q3_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/codegemma-1.1-7b-it-GGUF/resolve/main/codegemma-1.1-7b-it-Q3_K_M.gguf',
      'size': '~3.92 ГБ',
      'description': 'Полноразмерный 7B ассистент Google для архитектуры приложений, рефакторинга и сложных багов.',
    },
    {
      'family': 'Gemma',
      'name': 'Google Gemma 1.1 (2B) Instruct Q4_K_M',
      'params': '2.0B',
      'badge': 'Классика',
      'fileName': 'gemma-1.1-2b-it-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-1.1-2b-it-GGUF/resolve/main/gemma-1.1-2b-it-Q4_K_M.gguf',
      'size': '~1.5 ГБ',
      'description': 'Классическая легкая модель первого поколения Gemma от Google.',
    },
  ];
}
