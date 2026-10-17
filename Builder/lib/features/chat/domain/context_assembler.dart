import 'chat_message.dart';

class ContextManifest {
  final String id;
  final String requestId;
  final String category;
  final String catalogRevision;
  final String? activeInstruction;
  final List<String> memoryFacts;
  final List<String> knowledgeChunks;
  final List<Map<String, dynamic>> tools;
  final List<Map<String, String>> messages;
  final int estimatedTokens;
  final int reservedTokens;
  final DateTime assembledAtUtc;

  const ContextManifest({
    required this.id,
    required this.requestId,
    required this.category,
    required this.catalogRevision,
    this.activeInstruction,
    this.memoryFacts = const [],
    this.knowledgeChunks = const [],
    this.tools = const [],
    required this.messages,
    required this.estimatedTokens,
    required this.reservedTokens,
    required this.assembledAtUtc,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'request_id': requestId,
      'category': category,
      'catalog_revision': catalogRevision,
      'active_instruction': activeInstruction,
      'memory_facts': memoryFacts,
      'knowledge_chunks': knowledgeChunks,
      'tools': tools,
      'messages': messages,
      'estimated_tokens': estimatedTokens,
      'reserved_tokens': reservedTokens,
      'assembled_at_utc': assembledAtUtc.toIso8601String(),
    };
  }
}

class ContextAssembler {
  final int defaultReservedTokens;

  const ContextAssembler({this.defaultReservedTokens = 4096});

  /// Rough estimation: ~1 token per 3.5 chars for mixed Cyrillic/Latin/JSON
  int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 3.5).ceil() + 2;
  }

  ContextManifest assemble({
    required String manifestId,
    required String requestId,
    required String category,
    required String catalogRevision,
    required int contextWindow,
    String? activeInstruction,
    List<String> memoryFacts = const [],
    List<String> knowledgeChunks = const [],
    List<Map<String, dynamic>> tools = const [],
    required List<ChatMessage> conversationHistory,
    required String userPrompt,
    int? reservedTokens,
  }) {
    final reserved = reservedTokens ?? defaultReservedTokens;
    final budget = contextWindow > reserved ? (contextWindow - reserved) : (contextWindow ~/ 2);

    final List<Map<String, String>> finalWireMessages = [];

    // 1. Build system context if any instruction, memory facts or knowledge chunks exist
    final systemParts = <String>[];
    if (activeInstruction != null && activeInstruction.trim().isNotEmpty) {
      systemParts.add('Инструкция:\n$activeInstruction');
    }
    if (memoryFacts.isNotEmpty) {
      systemParts.add('Факты памяти:\n${memoryFacts.map((f) => '- $f').join('\n')}');
    }
    if (knowledgeChunks.isNotEmpty) {
      systemParts.add('Фрагменты знаний:\n${knowledgeChunks.map((c) => '[Источник]: $c').join('\n\n')}');
    }

    int currentEstimatedTokens = 0;

    String? systemPrompt;
    if (systemParts.isNotEmpty) {
      systemPrompt = systemParts.join('\n\n');
      currentEstimatedTokens += estimateTokens(systemPrompt);
      finalWireMessages.add({'role': 'system', 'content': systemPrompt});
    }

    // 2. User prompt tokens
    final userTokens = estimateTokens(userPrompt);
    currentEstimatedTokens += userTokens;

    // 3. Select relevant prior conversation history fitting the remaining budget (most recent first)
    final candidateHistory = conversationHistory
        .where((m) => m.status == MessageStatus.completed || m.status == MessageStatus.interrupted)
        .where((m) => m.role == MessageRole.user || m.role == MessageRole.assistant)
        .toList();

    final budgetedHistory = <Map<String, String>>[];
    for (int i = candidateHistory.length - 1; i >= 0; i--) {
      final msg = candidateHistory[i];
      final msgTokens = estimateTokens(msg.content);
      if (currentEstimatedTokens + msgTokens > budget) {
        // Exceeded budget, stop including older messages
        break;
      }
      currentEstimatedTokens += msgTokens;
      budgetedHistory.insert(0, {
        'role': msg.role.toDbValue(),
        'content': msg.content,
      });
    }

    finalWireMessages.addAll(budgetedHistory);
    finalWireMessages.add({'role': 'user', 'content': userPrompt});

    return ContextManifest(
      id: manifestId,
      requestId: requestId,
      category: category,
      catalogRevision: catalogRevision,
      activeInstruction: activeInstruction,
      memoryFacts: List.unmodifiable(memoryFacts),
      knowledgeChunks: List.unmodifiable(knowledgeChunks),
      tools: List.unmodifiable(tools),
      messages: List.unmodifiable(finalWireMessages),
      estimatedTokens: currentEstimatedTokens,
      reservedTokens: reserved,
      assembledAtUtc: DateTime.now().toUtc(),
    );
  }
}
