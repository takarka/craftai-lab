class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isGenerating;
  final double? tokensPerSecond;
  final int? totalTokens;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isGenerating = false,
    this.tokensPerSecond,
    this.totalTokens,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    bool? isGenerating,
    double? tokensPerSecond,
    int? totalTokens,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isGenerating: isGenerating ?? this.isGenerating,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      totalTokens: totalTokens ?? this.totalTokens,
    );
  }
}
