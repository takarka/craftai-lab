import 'package:flutter/material.dart';
import '../../../ui_kit/ui_kit.dart';

class ReportDialog extends StatefulWidget {
  final String requestId;

  const ReportDialog({super.key, required this.requestId});

  static Future<Map<String, String>?> show(BuildContext context, {required String requestId}) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => ReportDialog(requestId: requestId),
    );
  }

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String _selectedReason = 'inaccurate';
  final _commentController = TextEditingController();

  final Map<String, String> _reasons = {
    'inaccurate': 'Фактическая неточность или ошибка',
    'offensive': 'Неприемлемый или вредный контент',
    'off_topic': 'Ответ не по теме вопроса',
    'other': 'Другая причина',
  };

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сообщить о проблеме в ответе', style: BuilderType.h3),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Идентификатор запроса: ${widget.requestId.substring(0, 8)}...',
              style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary),
            ),
            const SizedBox(height: 16),
            const Text('Причина:', style: BuilderType.label),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _selectedReason,
              onChanged: (val) {
                if (val != null) setState(() => _selectedReason = val);
              },
              child: Column(
                children: _reasons.entries.map((entry) {
                  return RadioListTile<String>(
                    title: Text(entry.value, style: BuilderType.body),
                    value: entry.key,
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Комментарий (необязательно)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        BuilderButton(
          label: 'Отправить',
          onPressed: () {
            Navigator.of(context).pop({
              'reason': _selectedReason,
              'comment': _commentController.text.trim(),
            });
          },
        ),
      ],
    );
  }
}
