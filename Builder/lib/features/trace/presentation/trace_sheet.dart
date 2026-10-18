import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import '../domain/request_trace.dart';
import '../domain/trace_analogy.dart';
import '../trace_providers.dart';

enum TraceTab { schema, xray, analogy }

class TraceSheet extends ConsumerStatefulWidget {
  final String requestId;
  final VoidCallback? onClose;

  const TraceSheet({super.key, required this.requestId, this.onClose});

  static Future<void> show(BuildContext context, {required String requestId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            color: BuilderColors.surface,
            child: TraceSheet(
              requestId: requestId,
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<TraceSheet> createState() => _TraceSheetState();
}

class _TraceSheetState extends ConsumerState<TraceSheet> {
  TraceTab _activeTab = TraceTab.schema;

  @override
  Widget build(BuildContext context) {
    final traceAsync = ref.watch(traceProvider(widget.requestId));
    final isKk =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'kk';

    return traceAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: BuilderColors.warning),
              const SizedBox(height: 12),
              Text(
                isKk
                    ? 'Трассаны жүктеу мүмкін болмады'
                    : 'Не удалось загрузить трассу',
                style: BuilderType.title,
              ),
              const SizedBox(height: 8),
              Text(
                err.toString(),
                style: BuilderType.small,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      data: (trace) {
        if (trace == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.find_in_page_outlined,
                  size: 48,
                  color: BuilderColors.inkSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  isKk ? 'Трасса табылмады' : 'Трасса не найдена',
                  style: BuilderType.title,
                ),
                const SizedBox(height: 8),
                Text(
                  isKk
                      ? 'Бұл сұраныс үшін сақталған деректер жоқ.'
                      : 'Для этого запроса нет сохранённых данных.',
                  style: BuilderType.small,
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Column(
            children: [
              _buildHeader(context, trace, isKk),
              _buildSegmentedControl(isKk),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: switch (_activeTab) {
                    TraceTab.schema => _buildSchemaTab(context, trace, isKk),
                    TraceTab.xray => _buildXrayTab(context, trace, isKk),
                    TraceTab.analogy => _buildAnalogyTab(context, isKk),
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, RequestTrace trace, bool isKk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        border: Border(bottom: BorderSide(color: BuilderColors.line, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: BuilderColors.ink),
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
            tooltip: isKk ? 'Артқа' : 'Назад',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              isKk ? 'Қалай жұмыс істейді' : 'Под капотом',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: BuilderColors.ink,
              ),
            ),
          ),
          if (trace.isExample) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: BuilderColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BuilderColors.line),
              ),
              child: Text(
                isKk ? 'Үлгі' : 'Пример',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BuilderColors.inkSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFB74D)),
            ),
            child: Text(
              isKk ? 'Шетелдегі деректер' : 'Данные за рубежом',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE65100),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl(bool isKk) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE3ECFB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildSegmentButton(
            label: isKk ? 'Сұлба' : 'Схема',
            tab: TraceTab.schema,
          ),
          _buildSegmentButton(
            label: isKk ? 'Рентген' : 'Рентген',
            tab: TraceTab.xray,
          ),
          _buildSegmentButton(
            label: isKk ? 'Ұқсастық' : 'Аналогия',
            tab: TraceTab.analogy,
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({required String label, required TraceTab tab}) {
    final isActive = _activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTab = tab;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isActive
                ? [
                    const BoxShadow(
                      color: Color(0x1F0B1B33),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? BuilderColors.primary
                  : BuilderColors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: СХЕМА (SCHEMA)
  // -------------------------------------------------------------
  Widget _buildSchemaTab(BuildContext context, RequestTrace trace, bool isKk) {
    return ListView(
      key: const ValueKey('trace_schema_tab'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          isKk
              ? 'Бір сұраныс жолы: сіздің хабарламаңыздан жауапқа дейін.'
              : 'Путь одного запроса: от вашего сообщения до ответа.',
          style: BuilderType.small,
        ),
        const SizedBox(height: 14),

        // Aborted / Error notice if applicable
        if (trace.status == TraceStatus.interrupted)
          _buildStatusBanner(
            icon: Icons.pause_circle_outline,
            title: isKk ? 'Сұраныс тоқтатылды' : 'Запрос был остановлен',
            subtitle: isKk
                ? 'Пайдаланушы генерацияны өз бетінше тоқтатты.'
                : 'Пользователь вручную прервал генерацию ответа.',
            color: BuilderColors.warning,
          )
        else if (trace.status == TraceStatus.error)
          _buildStatusBanner(
            icon: Icons.error_outline,
            title: isKk
                ? 'Сұраныс қатемен аяқталды'
                : 'Ошибка выполнения запроса',
            subtitle:
                trace.errorCode ??
                (isKk ? 'Модель жауап бермеді.' : 'Модель не вернула ответ.'),
            color: BuilderColors.warning,
          ),

        // 5 Steps
        ...trace.steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final step = entry.value;
          final isLast = idx == trace.steps.length - 1;
          return _buildStepItem(step, isLast, trace, isKk);
        }),

        const SizedBox(height: 16),
        _buildMetricsRow(trace, isKk),
      ],
    );
  }

  Widget _buildStatusBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: BuilderColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(
    TraceStep step,
    bool isLast,
    RequestTrace trace,
    bool isKk,
  ) {
    final iconColor = step.location == LocationTag.abroad
        ? const Color(0xFFE8772E)
        : BuilderColors.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${step.stepIndex}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: BuilderColors.line,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BuilderColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${step.stepIndex} · ${step.title}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: BuilderColors.ink,
                          ),
                        ),
                      ),
                      _buildLocationChip(step.location, isKk),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: BuilderColors.inkSecondary,
                      height: 1.3,
                    ),
                  ),
                  if (step.stepIndex == 2) ...[
                    const SizedBox(height: 8),
                    _buildTokenDistributionBar(trace, isKk),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationChip(LocationTag location, bool isKk) {
    final String text;
    final bool isAbroad = location == LocationTag.abroad;

    switch (location) {
      case LocationTag.onDevice:
        text = isKk ? 'телефонда' : 'на телефоне';
        break;
      case LocationTag.craftAi:
        text = 'CraftAI';
        break;
      case LocationTag.abroad:
        text = isKk ? 'шетелде' : 'за рубежом';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isAbroad ? const Color(0xFFFFF3E0) : BuilderColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAbroad ? const Color(0xFFFFB74D) : BuilderColors.line,
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: isAbroad
              ? const Color(0xFFE65100)
              : BuilderColors.inkSecondary,
        ),
      ),
    );
  }

  Widget _buildTokenDistributionBar(RequestTrace trace, bool isKk) {
    final instruction = trace.layers
        .where((l) => l.type == TraceLayerType.instruction)
        .fold(0, (sum, l) => sum + l.tokenCount);
    final memory = trace.layers
        .where((l) => l.type == TraceLayerType.memory)
        .fold(0, (sum, l) => sum + l.tokenCount);
    final retrieval = trace.layers
        .where((l) => l.type == TraceLayerType.retrieval)
        .fold(0, (sum, l) => sum + l.tokenCount);
    final userPrompt = trace.layers
        .where((l) => l.type == TraceLayerType.userPrompt)
        .fold(0, (sum, l) => sum + l.tokenCount);

    final total = instruction + memory + retrieval + userPrompt;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 9,
            child: Row(
              children: [
                if (instruction > 0)
                  Expanded(
                    flex: instruction,
                    child: Container(color: BuilderColors.primary),
                  ),
                if (memory > 0)
                  Expanded(
                    flex: memory,
                    child: Container(color: const Color(0xFFE8772E)),
                  ),
                if (retrieval > 0)
                  Expanded(
                    flex: retrieval,
                    child: Container(color: const Color(0xFF7FA3E0)),
                  ),
                if (userPrompt > 0)
                  Expanded(
                    flex: userPrompt,
                    child: Container(color: BuilderColors.ink),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (instruction > 0)
              _buildLegendDot(
                BuilderColors.primary,
                '${isKk ? 'Нұсқаулық' : 'Инструкция'} $instruction',
              ),
            if (memory > 0)
              _buildLegendDot(
                const Color(0xFFE8772E),
                '${isKk ? 'Жад' : 'Память'} $memory',
              ),
            if (retrieval > 0)
              _buildLegendDot(
                const Color(0xFF7FA3E0),
                '${isKk ? 'Құжаттар' : 'Документы'} $retrieval',
              ),
            if (userPrompt > 0)
              _buildLegendDot(
                BuilderColors.ink,
                '${isKk ? 'Сұрақ' : 'Вопрос'} $userPrompt',
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isKk ? 'барлығы $total токен' : 'всего $total токенов',
          style: BuilderType.small.copyWith(fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: BuilderColors.inkSecondary),
        ),
      ],
    );
  }

  Widget _buildMetricsRow(RequestTrace trace, bool isKk) {
    final seconds = (trace.usage.durationMs / 1000).toStringAsFixed(1);
    final costDots = switch (trace.usage.costTier) {
      1 => '●○○',
      3 => '●●●',
      _ => '●●○',
    };

    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            value: '${trace.usage.totalTokens}',
            label: isKk ? 'токен' : 'токенов',
            sublabel: trace.usage.isServerReported
                ? (isKk ? 'сервер' : 'сервер')
                : (isKk ? 'бағалау' : 'оценка'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            value: '$seconds с',
            label: isKk ? 'уақыт' : 'время',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            value: costDots,
            label: isKk ? 'бағасы' : 'цена',
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String value,
    required String label,
    String? sublabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BuilderColors.line),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: BuilderColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: BuilderColors.inkSecondary),
          ),
          if (sublabel != null)
            Text(
              sublabel,
              style: TextStyle(fontSize: 9.5, color: BuilderColors.inkDisabled),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: РЕНТГЕН (X-RAY)
  // -------------------------------------------------------------
  Widget _buildXrayTab(BuildContext context, RequestTrace trace, bool isKk) {
    return ListView(
      key: const ValueKey('trace_xray_tab'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isKk
                    ? 'Модель жауап беру сәтінде көргеннің барлығы. Одан артық ештеңе жоқ.'
                    : 'Всё, что модель увидела в момент ответа. Больше у неё ничего нет.',
                style: BuilderType.small,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: trace.usage.isServerReported
                    ? const Color(0xFFE8F5E9)
                    : BuilderColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: trace.usage.isServerReported
                      ? const Color(0xFFA5D6A7)
                      : BuilderColors.line,
                ),
              ),
              child: Text(
                trace.usage.isServerReported
                    ? (isKk ? 'Сервер дерегі' : 'Сервер')
                    : (isKk ? 'Клиент бағалауы' : 'Оценка'),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: trace.usage.isServerReported
                      ? const Color(0xFF2E7D32)
                      : BuilderColors.inkSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        ...trace.layers.map((layer) => _buildLayerCard(layer, isKk)),

        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BuilderColors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${isKk ? 'сұраныс' : 'запрос'} ${trace.usage.promptTokens} + ${isKk ? 'жауап' : 'ответ'} ${trace.usage.completionTokens} = ${trace.usage.totalTokens} ${isKk ? 'токен' : 'токенов'}',
                style: BuilderType.small.copyWith(fontSize: 11.5),
              ),
              Text(
                '${(trace.usage.durationMs / 1000).toStringAsFixed(1)} с',
                style: BuilderType.small.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLayerCard(TraceLayer layer, bool isKk) {
    final borderColor = switch (layer.type) {
      TraceLayerType.instruction => BuilderColors.primary,
      TraceLayerType.memory => const Color(0xFFE8772E),
      TraceLayerType.retrieval => const Color(0xFF7FA3E0),
      TraceLayerType.userPrompt => BuilderColors.ink,
      TraceLayerType.response => const Color(0xFFE8772E),
      TraceLayerType.appAction => BuilderColors.line,
      _ => BuilderColors.line,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BuilderColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: borderColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            layer.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: BuilderColors.ink,
                            ),
                          ),
                        ),
                        if (layer.tokenCount > 0) ...[
                          Text(
                            '${layer.tokenCount} ${isKk ? 'ток.' : 'ток.'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: BuilderColors.inkSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (layer.extraChip != null) ...[
                          _buildLocationChip(layer.location, isKk),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F5FA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        layer.contentSnippet,
                        style: BuilderType.mono.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: АНАЛОГИЯ (ANALOGY)
  // -------------------------------------------------------------
  Widget _buildAnalogyTab(BuildContext context, bool isKk) {
    final analogy = TraceAnalogy.getForLanguage(isKk ? 'kk' : 'ru');

    return ListView(
      key: const ValueKey('trace_analogy_tab'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Story Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BuilderColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                analogy.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BuilderColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                analogy.story,
                style: TextStyle(
                  fontSize: 13.5,
                  color: BuilderColors.ink,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Text(
          analogy.subtitle,
          style: BuilderType.small.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        // Comparison Items
        ...analogy.items.map((item) => _buildAnalogyItemRow(item)),

        const SizedBox(height: 14),

        // Key takeaway card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE3ECFB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: BuilderColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 12.5,
                      color: BuilderColors.ink,
                      height: 1.35,
                    ),
                    children: [
                      TextSpan(
                        text: '${analogy.takeawayTitle} ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: analogy.takeawayText),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalogyItemRow(AnalogyItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BuilderColors.line),
              ),
              child: Text(
                item.lifeTerm,
                style: TextStyle(fontSize: 12.5, color: BuilderColors.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward,
              size: 16,
              color: BuilderColors.inkDisabled,
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE3ECFB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item.assistantTerm,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: BuilderColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
