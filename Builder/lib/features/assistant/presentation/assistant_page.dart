import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/presentation/foundation_pages.dart';
import '../../../ui_kit/ui_kit.dart';
import '../../onboarding/presentation/d02_consent_sheet.dart';
import '../../policy/policy_providers.dart';

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key, required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  bool _checking = true;
  bool _isAcknowledged = false;
  String? _cloudMessage;

  @override
  void initState() {
    super.initState();
    _checkPolicy();
  }

  Future<void> _checkPolicy() async {
    final repo = ref.read(policyRepositoryProvider);
    final ack = await repo.isPolicyAcknowledged(
      ownerId: widget.ownerId,
      policyId: 'd02_cross_border_transfer',
    );
    if (mounted) {
      setState(() {
        _isAcknowledged = ack;
        _checking = false;
      });
    }
  }

  Future<void> attemptCloudRequest() async {
    final repo = ref.read(policyRepositoryProvider);
    final ack = await repo.isPolicyAcknowledged(
      ownerId: widget.ownerId,
      policyId: 'd02_cross_border_transfer',
    );

    if (!ack) {
      if (!mounted) return;
      final result = await showD02ConsentSheet(context);
      if (result == true) {
        await repo.acknowledgePolicy(
          ownerId: widget.ownerId,
          policyId: 'd02_cross_border_transfer',
          policyVersion: 'v1.0',
        );
        if (mounted) {
          setState(() {
            _isAcknowledged = true;
            _cloudMessage = 'Запрос к облаку разрешён (согласие получено)';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _cloudMessage = 'Действие отменено: требуется согласие D02 для облачных запросов';
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _cloudMessage = 'Запрос к облаку выполнен';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.assistantTab),
        actions: const [LanguageSelector()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BuilderCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.assistantTab,
                          style: BuilderType.h2,
                        ),
                        const SizedBox(height: 8),
                        Text(s.assistantPending),
                        const SizedBox(height: 16),
                        if (!_checking) ...[
                          Row(
                            children: [
                              Icon(
                                _isAcknowledged
                                    ? Icons.check_circle_outline
                                    : Icons.shield_outlined,
                                color: _isAcknowledged
                                    ? BuilderColors.primary
                                    : BuilderColors.warning,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isAcknowledged
                                      ? 'Согласие на трансграничную передачу (D02): получено'
                                      : 'Режим без облака: согласие D02 отложено',
                                  style: BuilderType.small.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: _isAcknowledged
                                        ? BuilderColors.primary
                                        : BuilderColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  BuilderButton(
                    key: const Key('assistant.cloudAction'),
                    label: 'Отправить облачный запрос',
                    onPressed: attemptCloudRequest,
                  ),
                  if (_cloudMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _cloudMessage!,
                      key: const Key('assistant.cloudStatus'),
                      style: BuilderType.small.copyWith(
                        color: BuilderColors.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
