class ChatMessage {
  final String id;
  final String text;
  final String reasoning;
  final String? error;
  final String? contextText;
  final bool isUser;
  final DateTime timestamp;
  final bool isGenerating;
  final double? tokensPerSecond;
  final int? totalTokens;

  const ChatMessage({
    required this.id,
    required this.text,
    this.reasoning = '',
    this.error,
    this.contextText,
    required this.isUser,
    required this.timestamp,
    this.isGenerating = false,
    this.tokensPerSecond,
    this.totalTokens,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'reasoning': reasoning,
    'error': error,
    'contextText': contextText,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    'isGenerating': isGenerating,
    'tokensPerSecond': tokensPerSecond,
    'totalTokens': totalTokens,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    text: json['text'] as String,
    reasoning: json['reasoning'] as String? ?? '',
    error:
        json['error'] as String? ??
        (json['isGenerating'] == true
            ? 'Генерация прервана при закрытии приложения.'
            : null),
    contextText: json['contextText'] as String?,
    isUser: json['isUser'] as bool,
    timestamp: DateTime.parse(json['timestamp'] as String),
    // A restored message must never keep the input locked as generating.
    tokensPerSecond: (json['tokensPerSecond'] as num?)?.toDouble(),
    totalTokens: json['totalTokens'] as int?,
  );

  ChatMessage copyWith({
    String? id,
    String? text,
    String? reasoning,
    String? error,
    String? contextText,
    bool? isUser,
    DateTime? timestamp,
    bool? isGenerating,
    double? tokensPerSecond,
    int? totalTokens,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
      error: error ?? this.error,
      contextText: contextText ?? this.contextText,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isGenerating: isGenerating ?? this.isGenerating,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      totalTokens: totalTokens ?? this.totalTokens,
    );
  }
}
