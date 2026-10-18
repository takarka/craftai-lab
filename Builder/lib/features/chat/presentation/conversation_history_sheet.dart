import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../ui_kit/ui_kit.dart';
import '../chat_providers.dart';
import '../domain/conversation.dart';

class ConversationHistorySheet extends ConsumerStatefulWidget {
  final String ownerId;

  const ConversationHistorySheet({super.key, required this.ownerId});

  static Future<void> show(BuildContext context, {required String ownerId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ConversationHistorySheet(ownerId: ownerId),
    );
  }

  @override
  ConsumerState<ConversationHistorySheet> createState() =>
      _ConversationHistorySheetState();
}

class _ConversationHistorySheetState
    extends ConsumerState<ConversationHistorySheet> {
  bool _ephemeralMode = false;

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider(widget.ownerId));
    final chatState = ref.watch(chatSessionProvider(widget.ownerId));
    final activeId = chatState.activeConversation?.id;

    return Material(
      color: BuilderColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('История разговоров', style: BuilderType.h3),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Ephemeral mode switch
            SwitchListTile(
              title: const Text(
                'Режим без сохранения истории',
                style: BuilderType.body,
              ),
              subtitle: const Text(
                'Сообщения не записываются на устройство',
                style: BuilderType.small,
              ),
              value: _ephemeralMode,
              activeThumbColor: BuilderColors.primary,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _ephemeralMode = val),
            ),
            const SizedBox(height: 12),
            BuilderButton(
              key: const Key('chat.newConversationBtn'),
              label: _ephemeralMode
                  ? 'Новый временный разговор'
                  : 'Новый разговор',
              onPressed: () async {
                Navigator.of(context).pop();
                await ref
                    .read(chatSessionProvider(widget.ownerId).notifier)
                    .startNewConversation(
                      retentionPolicy: _ephemeralMode
                          ? RetentionPolicy.ephemeral
                          : RetentionPolicy.persistent,
                    );
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Expanded(
              child: conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'Нет сохранённых разговоров',
                        style: BuilderType.body,
                      ),
                    )
                  : ListView.separated(
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final conv = conversations[index];
                        final isSelected = conv.id == activeId;

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: BuilderColors.background,
                          leading: Icon(
                            conv.isEphemeral
                                ? Icons.visibility_off_outlined
                                : Icons.chat_bubble_outline,
                            color: isSelected
                                ? BuilderColors.primary
                                : BuilderColors.inkSecondary,
                          ),
                          title: Text(
                            conv.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BuilderType.body.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? BuilderColors.primary
                                  : BuilderColors.ink,
                            ),
                          ),
                          subtitle: Text(
                            conv.isEphemeral
                                ? 'Временный (не сохраняется)'
                                : '${conv.activityAtUtc.toLocal().day}.${conv.activityAtUtc.toLocal().month.toString().padLeft(2, '0')}.${conv.activityAtUtc.toLocal().year}',
                            style: BuilderType.small.copyWith(
                              color: BuilderColors.inkSecondary,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            color: BuilderColors.warning,
                            onPressed: () async {
                              await ref
                                  .read(
                                    conversationsProvider(
                                      widget.ownerId,
                                    ).notifier,
                                  )
                                  .delete(conv.id);
                              if (isSelected) {
                                await ref
                                    .read(
                                      chatSessionProvider(
                                        widget.ownerId,
                                      ).notifier,
                                    )
                                    .startNewConversation();
                              }
                            },
                          ),
                          onTap: () async {
                            Navigator.of(context).pop();
                            if (!isSelected) {
                              await ref
                                  .read(
                                    chatSessionProvider(
                                      widget.ownerId,
                                    ).notifier,
                                  )
                                  .switchConversation(conv.id);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
