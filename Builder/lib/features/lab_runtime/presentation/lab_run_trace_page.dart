import 'package:flutter/material.dart';

import '../domain/lab_run_models.dart';
import '../infrastructure/lab_runtime_api.dart';

class LabRunTracePage extends StatefulWidget {
  final String runId;
  final LabRuntimeApi api;

  const LabRunTracePage({
    super.key,
    required this.runId,
    required this.api,
  });

  @override
  State<LabRunTracePage> createState() => _LabRunTracePageState();
}

class _LabRunTracePageState extends State<LabRunTracePage> {
  LabRun? _run;
  String? _error;
  bool _loading = true;
  final Set<String> _deletedMaterialIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final run = await widget.api.getRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = run;
        _loading = false;
      });
    } on LabApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.message} ${e.nextStep}';
        _loading = false;
      });
    }
  }

  Future<void> _deleteSavedMaterial(String agentId, String materialId) async {
    try {
      await widget.api.deleteMaterial(agentId: agentId, materialId: materialId);
      if (!mounted) return;
      setState(() {
        _deletedMaterialIds.add(materialId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранённый материал удалён.')),
      );
    } on LabApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Как выполнено')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildTraceBody(_run!),
    );
  }

  Widget _buildTraceBody(LabRun run) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Модель: ${run.modelId}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Версия конфигурации: ${run.agentVersionId} (epoch ${run.epoch})'),
                Text('Статус: ${_statusLabel(run.status)}'),
                if (run.stopReason != null)
                  Text('Причина остановки: ${run.stopReason}'),
                Text('Вызовов инструментов: ${run.toolCallsCount} из 3'),
                Text('Активное время: ${run.activeElapsedMs} мс'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'События выполнения',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final evt in run.events) _buildEventCard(run, evt),
      ],
    );
  }

  Widget _buildEventCard(LabRun run, LabRunEvent evt) {
    final result = evt.payload['result'];
    final materialId =
        result is Map ? result['material_id'] as String? : null;
    final hasError =
        evt.eventType == 'tool_rejected' ||
        (result is Map && result['error'] != null);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${evt.sequence} · ${evt.eventType}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Semantics(
                  label: hasError ? 'Статус: ошибка' : 'Статус: выполнено',
                  child: Text(
                    hasError ? 'Ошибка' : 'ОК',
                    style: TextStyle(
                      color: hasError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (evt.payload['tool_name'] != null)
              Text('Инструмент: ${evt.payload['tool_name']}'),
            if (evt.payload['params'] != null)
              Text('Параметры: ${evt.payload['params']}'),
            if (materialId != null && materialId.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('ID материала: $materialId'),
              if (run.status == 'cancelled' &&
                  !_deletedMaterialIds.contains(materialId))
                TextButton.icon(
                  onPressed: () =>
                      _deleteSavedMaterial(run.agentId, materialId),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить сохранённый материал'),
                ),
              if (_deletedMaterialIds.contains(materialId))
                const Text('Материал удалён.'),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'running' => 'Выполняется',
      'awaiting_confirmation' => 'Ожидает подтверждения',
      'completed' => 'Завершён',
      'cancelled' => 'Отменён',
      'failed' => 'Ошибка',
      _ => status,
    };
  }
}
