import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/ui_kit.dart';
import '../domain/mcp_models.dart';
import '../infrastructure/mcp_client.dart';
import 'mcp_providers.dart';

/// Screen S44: External Integrations & Model Context Protocol (F15-01, F15-02, F15-06, F15-07, F15-10).
class McpPage extends ConsumerStatefulWidget {
  final String ownerId;

  const McpPage({super.key, required this.ownerId});

  @override
  ConsumerState<McpPage> createState() => _McpPageState();
}

class _McpPageState extends ConsumerState<McpPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _showLogs = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mcpControllerProvider(widget.ownerId));
    final controller = ref.read(mcpControllerProvider(widget.ownerId).notifier);
    final client = ref.watch(mcpClientProvider);

    return Scaffold(
      backgroundColor: BuilderColors.background,
      appBar: AppBar(
        backgroundColor: BuilderColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Внешние интеграции (MCP)',
          style: BuilderTypography.titleMedium.copyWith(
            color: BuilderColors.ink,
          ),
        ),
        actions: [
          // "Готово" button returns to S43 ToolsPage (F15 acceptance criteria)
          TextButton(
            key: const Key('mcp.doneBtn'),
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: BuilderColors.primary,
            ),
            child: Text(
              'Готово',
              style: BuilderTypography.labelMedium.copyWith(
                color: BuilderColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: BuilderSpace.xs),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(BuilderSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Data Disclosure Banner (F15-02)
                  Container(
                    key: const Key('mcp.disclosureBanner'),
                    padding: const EdgeInsets.all(BuilderSpace.sm),
                    decoration: BoxDecoration(
                      color: BuilderColors.surface,
                      borderRadius: BorderRadius.circular(BuilderRadii.card),
                      border: Border.all(color: BuilderColors.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: BuilderIcon(
                            BuilderGlyph.info,
                            size: 20,
                            color: BuilderColors.primary,
                          ),
                        ),
                        const SizedBox(width: BuilderSpace.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Стандарт Model Context Protocol (MCP)',
                                style: BuilderTypography.labelMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: BuilderColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'MCP позволяет ассистенту безопасно обращаться к внешним каталогам знаний через доверенный шлюз. '
                                'Подключение выполняется через ваш аккаунт CraftAI. Запросы не содержат персональных данных учеников.',
                                style: BuilderTypography.bodySmall.copyWith(
                                  color: BuilderColors.inkSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BuilderSpace.md),

                  // Error Banner
                  if (state.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(BuilderSpace.sm),
                      decoration: BoxDecoration(
                        color: BuilderColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(BuilderRadii.tile),
                        border: Border.all(
                          color: BuilderColors.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        state.errorMessage!,
                        style: BuilderTypography.bodySmall.copyWith(
                          color: BuilderColors.warning,
                        ),
                      ),
                    ),
                    const SizedBox(height: BuilderSpace.md),
                  ],

                  // Success Message Banner
                  if (state.savedNoteMessage != null) ...[
                    Container(
                      key: const Key('mcp.savedNoteBanner'),
                      padding: const EdgeInsets.all(BuilderSpace.sm),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(BuilderRadii.tile),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          const BuilderIcon(
                            BuilderGlyph.check,
                            size: 18,
                            color: Colors.green,
                          ),
                          const SizedBox(width: BuilderSpace.xs),
                          Expanded(
                            child: Text(
                              state.savedNoteMessage!,
                              style: BuilderTypography.bodySmall.copyWith(
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BuilderSpace.md),
                  ],

                  // 2. Working Connector: Каталог уроков CraftAI (F15-01)
                  _buildCraftAiConnectorCard(state, controller),
                  const SizedBox(height: BuilderSpace.md),

                  // 3. Educational Protocol Viewer ("Под капотом", F15-07)
                  if (state.isCraftAiConnected) ...[
                    _buildEducationalRpcLogSection(client),
                    const SizedBox(height: BuilderSpace.md),
                  ],

                  // 4. Coming Soon Connectors (F15-10)
                  Text(
                    'Планируемые интеграции (Скоро)',
                    style: BuilderTypography.titleSmall.copyWith(
                      color: BuilderColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: BuilderSpace.xs),
                  ...McpConnector.allConnectors
                      .where((c) => c.isComingSoon)
                      .map((c) => _buildComingSoonConnectorCard(c)),

                  const SizedBox(height: BuilderSpace.lg),
                ],
              ),
            ),
    );
  }

  Widget _buildCraftAiConnectorCard(McpState state, McpNotifier controller) {
    final connector = McpConnector.allConnectors[0];

    return Container(
      key: const Key('mcp.card.craftai_lessons'),
      padding: const EdgeInsets.all(BuilderSpace.md),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        border: Border.all(
          color: state.isCraftAiConnected
              ? BuilderColors.primary
              : BuilderColors.line,
          width: state.isCraftAiConnected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIconTile(BuilderGlyph.doc, warm: true),
              const SizedBox(width: BuilderSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connector.title,
                      style: BuilderTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: BuilderColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connector.subtitle,
                      style: BuilderTypography.bodySmall.copyWith(
                        color: BuilderColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(
                state.isCraftAiConnected
                    ? McpConnectionStatus.connected
                    : McpConnectionStatus.disconnected,
              ),
            ],
          ),
          const SizedBox(height: BuilderSpace.sm),

          Text(
            connector.description,
            style: BuilderTypography.bodySmall.copyWith(
              color: BuilderColors.ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: BuilderSpace.sm),

          // Connect / Disconnect button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: Key(
                state.isCraftAiConnected
                    ? 'mcp.disconnectBtn'
                    : 'mcp.connectBtn',
              ),
              icon: BuilderIcon(
                state.isCraftAiConnected
                    ? BuilderGlyph.close
                    : BuilderGlyph.bolt,
                size: 18,
                color: state.isCraftAiConnected
                    ? Colors.red.shade700
                    : Colors.white,
              ),
              label: Text(
                state.isCraftAiConnected
                    ? 'Отключить каталог'
                    : 'Подключить каталог уроков',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                backgroundColor: state.isCraftAiConnected
                    ? Colors.red.shade50
                    : BuilderColors.primary,
                foregroundColor: state.isCraftAiConnected
                    ? Colors.red.shade700
                    : Colors.white,
                elevation: 0,
              ),
              onPressed: () {
                if (state.isCraftAiConnected) {
                  controller.disconnectCraftAi();
                } else {
                  controller.connectCraftAi();
                }
              },
            ),
          ),

          // When connected: Show capabilities and search tool (F15-02, F15-06)
          if (state.isCraftAiConnected) ...[
            const Divider(height: BuilderSpace.lg),
            Text(
              'Доступные функции каталога (tools/list):',
              style: BuilderTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: BuilderColors.ink,
              ),
            ),
            const SizedBox(height: BuilderSpace.xs),
            ...state.activeTools.map((tool) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.check,
                      size: 16,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: BuilderSpace.xs),
                    Expanded(
                      child: Text(
                        '${tool.name} — ${tool.displayName}',
                        style: BuilderTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                          color: BuilderColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: BuilderSpace.sm),

            // Interactive lesson search bar
            TextField(
              key: const Key('mcp.searchInput'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск урока (например: теорема, уравнения, физика)',
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: BuilderIcon(BuilderGlyph.search, size: 18),
                ),
                suffixIcon: IconButton(
                  key: const Key('mcp.searchSubmitBtn'),
                  icon: const BuilderIcon(BuilderGlyph.chevron, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => controller.search(_searchController.text),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BuilderRadii.tile),
                  borderSide: const BorderSide(color: BuilderColors.line),
                ),
              ),
              onSubmitted: (q) => controller.search(q),
            ),
            const SizedBox(height: BuilderSpace.sm),

            // Search results list (F15-06)
            if (state.isSearching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state.searchResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Уроки по запросу не найдены. Попробуйте другой запрос.',
                  style: BuilderTypography.bodySmall.copyWith(
                    color: BuilderColors.inkSecondary,
                  ),
                ),
              )
            else ...[
              Text(
                'Найдено уроков: ${state.searchResults.length}',
                style: BuilderTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: BuilderColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 6),
              ...state.searchResults.map(
                (item) => _buildLessonItemTile(item, controller),
              ),
            ],

            // Selected lesson preview modal / card
            if (state.selectedLesson != null) ...[
              const SizedBox(height: BuilderSpace.sm),
              _buildLessonDetailCard(state.selectedLesson!, controller),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLessonItemTile(McpLessonSummary item, McpNotifier controller) {
    return Container(
      key: Key('mcp.lessonItem.${item.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: BuilderColors.background,
        borderRadius: BorderRadius.circular(BuilderRadii.tile),
        border: Border.all(color: BuilderColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BuilderColors.primaryTint,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${item.subject} · ${item.grade} класс',
                  style: BuilderTypography.bodySmall.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: BuilderColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                key: Key('mcp.openLessonBtn.${item.id}'),
                onPressed: () => controller.selectLesson(item.id),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Открыть'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            style: BuilderTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: BuilderColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.summary,
            style: BuilderTypography.bodySmall.copyWith(
              color: BuilderColors.inkSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLessonDetailCard(
    McpLessonDetail detail,
    McpNotifier controller,
  ) {
    return Container(
      key: const Key('mcp.lessonDetailCard'),
      padding: const EdgeInsets.all(BuilderSpace.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        border: Border.all(color: BuilderColors.primary),
        boxShadow: BuilderShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.title,
                  style: BuilderTypography.titleSmall.copyWith(
                    color: BuilderColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const Key('mcp.closeDetailBtn'),
                icon: const BuilderIcon(BuilderGlyph.close, size: 18),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => controller.clearSelection(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${detail.subject} · ${detail.grade} класс · Автор: ${detail.author}',
            style: BuilderTypography.bodySmall.copyWith(
              color: BuilderColors.inkSecondary,
            ),
          ),
          const Divider(height: BuilderSpace.md),
          Text(
            detail.content,
            style: BuilderTypography.bodySmall.copyWith(
              color: BuilderColors.ink,
              height: 1.4,
            ),
          ),
          const SizedBox(height: BuilderSpace.md),

          // Save to notes button with confirmation (F15-06)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('mcp.saveToNotesBtn'),
              icon: const BuilderIcon(BuilderGlyph.memory, size: 18),
              label: const Text('Сохранить конспект в личные заметки'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                backgroundColor: BuilderColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => controller.saveLessonToNotes(detail),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEducationalRpcLogSection(McpClient client) {
    return Container(
      key: const Key('mcp.rpcLogCard'),
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        border: Border.all(color: BuilderColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('mcp.toggleLogsBtn'),
            onTap: () => setState(() => _showLogs = !_showLogs),
            child: Row(
              children: [
                const BuilderIcon(
                  BuilderGlyph.code,
                  size: 18,
                  color: BuilderColors.primary,
                ),
                const SizedBox(width: BuilderSpace.xs),
                Expanded(
                  child: Text(
                    'Протокол обмена MCP (Под капотом)',
                    style: BuilderTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: BuilderColors.ink,
                    ),
                  ),
                ),
                Icon(
                  _showLogs ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: BuilderColors.inkSecondary,
                ),
              ],
            ),
          ),
          if (_showLogs) ...[
            const SizedBox(height: BuilderSpace.xs),
            Text(
              'Реальные JSON-RPC 2.0 вызовы к шлюзу без секретов авторизации (F15-07):',
              style: BuilderTypography.bodySmall.copyWith(
                color: BuilderColors.inkSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...client.recentLogs.take(3).map((log) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Метод: ${log.method} (${log.durationMs} мс)',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Запрос:\n${log.requestJson}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ответ:\n${log.responseJson}',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildComingSoonConnectorCard(McpConnector connector) {
    return Container(
      key: Key('mcp.comingSoonCard.${connector.id}'),
      margin: const EdgeInsets.only(bottom: BuilderSpace.xs),
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.tile),
        border: Border.all(color: BuilderColors.line.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuilderIconTile(connector.glyph, warm: false),
          const SizedBox(width: BuilderSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connector.title,
                  style: BuilderTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: BuilderColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  connector.subtitle,
                  style: BuilderTypography.bodySmall.copyWith(
                    color: BuilderColors.inkSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          _buildStatusBadge(McpConnectionStatus.comingSoon),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(McpConnectionStatus status) {
    Color bg;
    Color fg;
    switch (status) {
      case McpConnectionStatus.connected:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case McpConnectionStatus.connecting:
        bg = BuilderColors.primaryTint;
        fg = BuilderColors.primary;
        break;
      case McpConnectionStatus.disconnected:
        bg = BuilderColors.background;
        fg = BuilderColors.inkSecondary;
        break;
      case McpConnectionStatus.comingSoon:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade600;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.label,
        style: BuilderTypography.bodySmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
