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

  static Future<SkillPracticeProgress> checkProgress(
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
    return progress(ownerId, skills, threads);
  }

  static bool isMet(
    String ownerId,
    List<SkillScenario> skills,
    List<List<ChatMessage>> threads,
  ) => progress(ownerId, skills, threads).isMet;

  /// Explains which practice conditions hold for the closest skill, so the
  /// lesson can say what is still missing instead of a generic refusal.
  static SkillPracticeProgress progress(
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
    var best = SkillPracticeProgress(hasSkill: skills.isNotEmpty);
    for (final skill in skills) {
      final matching = runs.where((r) => r.skill.id == skill.id).toList();
      final inputs = matching
          .map(
            (r) => jsonEncode([
              for (final key in skill.requiredInputs) r.inputs[key]?.trim(),
            ]),
          )
          .toSet();
      final current = SkillPracticeProgress(
        hasSkill: true,
        hasInputs: skill.requiredInputs.isNotEmpty,
        distinctInputRuns: inputs.length,
        improved: matching.any(
          (r) =>
              r.skill.revision < skill.revision &&
              (jsonEncode(r.skill.steps) != jsonEncode(skill.steps) ||
                  jsonEncode(r.skill.qualityCriteria) !=
                      jsonEncode(skill.qualityCriteria)),
        ),
        currentWasRun: matching.any(
          (r) => jsonEncode(r.skill.toJson()) == jsonEncode(skill.toJson()),
        ),
      );
      if (current.isMet) return current;
      if (current.score >= best.score) best = current;
    }
    return best;
  }
}

class SkillPracticeProgress {
  const SkillPracticeProgress({
    this.hasSkill = false,
    this.hasInputs = false,
    this.distinctInputRuns = 0,
    this.improved = false,
    this.currentWasRun = false,
  });
  final bool hasSkill;

  /// A skill without inputs can never be run on two different inputs.
  final bool hasInputs;
  final int distinctInputRuns;

  /// An earlier run used older steps or criteria than the saved version.
  final bool improved;

  /// The saved (latest) version has its own completed run.
  final bool currentWasRun;

  bool get twoInputs => distinctInputRuns >= 2;
  bool get isMet => twoInputs && improved && currentWasRun;
  int get score =>
      (hasSkill ? 1 : 0) +
      (hasInputs ? 1 : 0) +
      (twoInputs ? 2 : distinctInputRuns) +
      (improved ? 1 : 0) +
      (currentWasRun ? 1 : 0);
}
