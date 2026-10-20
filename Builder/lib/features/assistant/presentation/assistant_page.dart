import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../assistant_providers.dart';
import '../../chat/chat_providers.dart';
import '../../chat/domain/conversation.dart';
import '../../chat/presentation/conversation_history_sheet.dart';
import '../../models/domain/model_category.dart';
import '../../models/model_providers.dart';
import '../../course/domain/course_topic.dart';
import '../../course/presentation/course_character.dart';

/// The assistant tab is a home screen. Conversation input lives on /chat.
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key, required this.ownerId});
  final String ownerId;

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  bool _openingChat = false;

  String t(String ru, String kk) =>
      Localizations.localeOf(context).languageCode == 'kk' ? kk : ru;

  Future<void> _openChat([Conversation? conversation]) async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    try {
      final session = ref.read(chatSessionProvider(widget.ownerId).notifier);
      if (conversation == null) {
        await session.startNewConversation();
      } else {
        await session.switchConversation(conversation.id);
      }
      if (mounted) await context.push('/chat');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Не удалось открыть чат. Попробуйте ещё раз.',
                'Чатты ашу мүмкін болмады. Қайталап көріңіз.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = widget.ownerId;
    final s = AppLocalizations.of(context);
    final conversations = ref.watch(conversationsProvider(ownerId));
    final levelsAsync = ref.watch(completedCourseLevelsProvider(ownerId));
    final levels = levelsAsync.asData?.value;
    final courseLevel = CourseTopic.highestCompletedOrder(levels ?? const {});
    final config = ref.watch(assistantConfigProvider(ownerId)).asData?.value;
    final name = config?.name.trim();
    final category = ref.watch(selectedCategoryProvider(ownerId));
    final categoryLabel = switch (category) {
      ModelCategory.fast => s.modelsFastTitle,
      ModelCategory.standard => s.modelsStandardTitle,
      ModelCategory.advanced => s.modelsAdvancedTitle,
    };
    final (title, description) = levelsAsync.hasError
        ? (
            t('Состояние пока недоступно', 'Күйі әзірге қолжетімсіз'),
            t(
              'Не удалось загрузить возможности ассистента. Попробуйте открыть экран ещё раз.',
              'Ассистент мүмкіндіктері жүктелмеді. Экранды қайта ашып көріңіз.',
            ),
          )
        : levels == null
        ? (
            t('Знакомимся с ассистентом', 'Ассистентпен танысу'),
            t('Загружаем его текущее состояние…', 'Ағымдағы күйі жүктелуде…'),
          )
        : switch (courseLevel) {
            0 => (
              t('Готов к первым задачам', 'Алғашқы тапсырмаларға дайын'),
              t(
                'Задайте вопрос или обсудите идею урока. Настройте ассистента под себя, чтобы ответы стали точнее.',
                'Сұрақ қойыңыз немесе сабақ идеясын талқылаңыз. Нақты жауаптар алу үшін ассистентті өзіңізге бейімдеңіз.',
              ),
            ),
            1 => (
              t('Учитывает ваши настройки', 'Баптауларыңызды ескереді'),
              t(
                'Предмет, классы и язык помогают ассистенту отвечать ближе к вашим задачам.',
                'Пән, сыныптар және тіл ассистентке тапсырмаларыңызға сай жауап беруге көмектеседі.',
              ),
            ),
            2 => (
              t('Следует вашим инструкциям', 'Нұсқауларыңызды орындайды'),
              t(
                'Добавленные правила задают тон и формат ответов. Больше не нужно повторять их в каждом разговоре.',
                'Қосылған ережелер жауаптардың мәнері мен пішімін анықтайды. Оларды әр әңгімеде қайталау қажет емес.',
              ),
            ),
            3 => (
              t('Запускает ваши навыки', 'Дағдыларыңызды іске қосады'),
              t(
                'Сохранённый сценарий помогает повторять задачу с новыми входными данными.',
                'Сақталған сценарий тапсырманы жаңа кіріс деректерімен қайталауға көмектеседі.',
              ),
            ),
            4 => (
              t(
                'Работает с вашими материалами',
                'Материалдарыңызбен жұмыс істейді',
              ),
              t(
                'Использует загруженные документы и ваши инструкции, чтобы помогать с учебными задачами.',
                'Оқу тапсырмаларына көмектесу үшін жүктелген құжаттар мен нұсқауларыңызды пайдаланады.',
              ),
            ),
            5 => (
              t('Помнит важный контекст', 'Маңызды контексті есте сақтайды'),
              t(
                'Сохранённые факты помогают учитывать особенности вашего класса и продолжать работу с нужным контекстом.',
                'Сақталған деректер сыныбыңыздың ерекшеліктерін ескеріп, жұмысты қажетті контекспен жалғастыруға көмектеседі.',
              ),
            ),
            _ => (
              t('Помогает переходить к действиям', 'Іске көшуге көмектеседі'),
              t(
                'К настройкам, знаниям и памяти добавлены инструменты. Выбирайте нужные возможности для своих задач.',
                'Баптауларға, білімге және жадқа құралдар қосылды. Тапсырмаларыңызға қажетті мүмкіндіктерді таңдаңыз.',
              ),
            ),
          };

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              children: [
                Center(
                  child: Container(
                    key: const Key('assistant.character'),
                    width: 216,
                    height: 216,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          BuilderColors.primaryTint,
                          BuilderColors.primaryTint.withValues(alpha: .45),
                          BuilderColors.primaryTint.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: CourseCharacter(
                      completedLevels: levels ?? const {},
                      size: 168,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name?.isNotEmpty == true
                      ? name!
                      : t('Ваш ассистент', 'Сіздің ассистентіңіз'),
                  style: BuilderType.small.copyWith(
                    color: BuilderColors.inkSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  key: const Key('assistant.stateTitle'),
                  style: BuilderType.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    description,
                    key: const Key('assistant.stateDescription'),
                    style: BuilderType.body.copyWith(
                      color: BuilderColors.inkSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('assistant.newChatFab'),
                  onPressed: _openingChat ? null : () => _openChat(),
                  style: FilledButton.styleFrom(
                    backgroundColor: BuilderColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _openingChat
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_comment_outlined, size: 20),
                  label: Text(t('Новый чат', 'Жаңа чат')),
                ),
                const SizedBox(height: 12),
                BuilderCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        key: const Key('assistant.chooseModel'),
                        leading: const Icon(
                          Icons.auto_awesome_outlined,
                          color: BuilderColors.primary,
                        ),
                        title: Text(
                          t('Модель ответов', 'Жауап моделі'),
                          style: BuilderType.title,
                        ),
                        subtitle: Text(categoryLabel, style: BuilderType.small),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => context.push('/assistant/models'),
                      ),
                      const Divider(height: 1, indent: 56, endIndent: 16),
                      ListTile(
                        key: const Key('assistant.settingsBtn'),
                        leading: const Icon(
                          Icons.tune,
                          color: BuilderColors.primary,
                        ),
                        title: Text(
                          t('Настроить ассистента', 'Ассистентті баптау'),
                          style: BuilderType.title,
                        ),
                        subtitle: Text(
                          t(
                            'Инструкции, знания и возможности',
                            'Нұсқаулар, білім және мүмкіндіктер',
                          ),
                          style: BuilderType.small,
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => context.push('/assistant/settings'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('Последние чаты', 'Соңғы чаттар'),
                        style: BuilderType.h3,
                      ),
                    ),
                    IconButton(
                      key: const Key('assistant.historyBtn'),
                      tooltip: t('История разговоров', 'Әңгімелер тарихы'),
                      icon: const Icon(Icons.history_outlined),
                      onPressed: () => ConversationHistorySheet.show(
                        context,
                        ownerId: ownerId,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (conversations.isEmpty)
                  BuilderCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Начните с одной идеи', 'Бір идеядан бастаңыз'),
                          style: BuilderType.title,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t(
                            'Попросите объяснить тему, придумать задание или составить план урока. Сохранённые разговоры появятся здесь.',
                            'Тақырыпты түсіндіруді, тапсырма ойлап табуды немесе сабақ жоспарын жасауды сұраңыз. Сақталған әңгімелер осында пайда болады.',
                          ),
                          style: BuilderType.small.copyWith(
                            color: BuilderColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...conversations
                      .take(3)
                      .map(
                        (conversation) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _RecentChatTile(
                            conversation: conversation,
                            onTap: () => _openChat(conversation),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentChatTile extends StatelessWidget {
  const _RecentChatTile({required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => BuilderCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        const BuilderIconTile(BuilderGlyph.robot, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BuilderType.title,
              ),
              const SizedBox(height: 2),
              Text(
                conversation.isEphemeral
                    ? 'Временный чат'
                    : 'Открыт ${conversation.activityAtUtc.toLocal().day}.${conversation.activityAtUtc.toLocal().month.toString().padLeft(2, '0')}',
                style: BuilderType.small,
              ),
            ],
          ),
        ),
        const BuilderIcon(
          BuilderGlyph.chevron,
          size: 18,
          color: BuilderColors.inkSecondary,
        ),
      ],
    ),
  );
}
