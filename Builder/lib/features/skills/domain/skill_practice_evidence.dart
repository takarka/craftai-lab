import 'dart:convert';

import '../../chat/domain/chat_message.dart';
import '../../chat/domain/chat_repository.dart';
import 'skill_request.dart';
import 'skill_scenario.dart';

abstract final class SkillPracticeEvidence {
  static Future<bool> check(
    String ownerId,
    List<SkillScenario> skills,
    ChatRepository repository,
  ) async {
    final threads = <List<ChatMessage>>[];
    for (final conversation in await repository.getConversations(
      ownerId: ownerId,
    )) {
      if (conversation.ownerId == ownerId && !conversation.isEphemeral) {
        threads.add(
          await repository.getMessages(conversationId: conversation.id),
        );
      }
    }
    return isMet(ownerId, skills, threads);
  }

  static bool isMet(
    String ownerId,
    List<SkillScenario> skills,
    List<List<ChatMessage>> threads,
  ) {
    final runs = <SkillRequest>[];
    for (final thread in threads) {
      SkillRequest? pending;
      String? conversationId;
      for (final message in thread) {
        if (message.ownerId != ownerId) {
          pending = null;
          continue;
        }
        if (message.isUser) {
          pending = SkillRequest.tryParse(message.content);
          conversationId = message.conversationId;
        } else if (message.isAssistant) {
          if (pending != null &&
              message.conversationId == conversationId &&
              message.status == MessageStatus.completed &&
              message.content.trim().isNotEmpty) {
            runs.add(pending);
          }
          pending = null;
        }
      }
    }
    for (final skill in skills) {
      final matching = runs.where((r) => r.skill.id == skill.id).toList();
      final inputs = matching
          .map(
            (r) => jsonEncode([
              for (final key in skill.requiredInputs) r.inputs[key]?.trim(),
            ]),
          )
          .toSet();
      if (inputs.length < 2) continue;
      final currentWasRun = matching.any(
        (r) => jsonEncode(r.skill.toJson()) == jsonEncode(skill.toJson()),
      );
      final improved = matching.any(
        (r) =>
            r.skill.revision < skill.revision &&
            (jsonEncode(r.skill.steps) != jsonEncode(skill.steps) ||
                jsonEncode(r.skill.qualityCriteria) !=
                    jsonEncode(skill.qualityCriteria)),
      );
      if (currentWasRun && improved) return true;
    }
    return false;
  }
}
