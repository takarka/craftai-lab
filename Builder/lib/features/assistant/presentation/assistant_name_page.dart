import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../assistant_providers.dart';

class AssistantNamePage extends ConsumerStatefulWidget {
  const AssistantNamePage({super.key, required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<AssistantNamePage> createState() => _AssistantNamePageState();
}

class _AssistantNamePageState extends ConsumerState<AssistantNamePage> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = ref
        .read(assistantConfigProvider(widget.ownerId))
        .asData
        ?.value;
    _controller = TextEditingController(text: config?.name ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate(String value, AppLocalizations s) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _error = s.assistantNameEmptyError;
    } else if (trimmed.characters.length > 30) {
      _error = s.assistantNameTooLongError;
    } else {
      _error = null;
    }
  }

  Future<void> _handleSave() async {
    final s = AppLocalizations.of(context);
    final text = _controller.text.trim();
    _validate(text, s);
    if (_error != null) {
      setState(() {});
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await ref
          .read(assistantControllerProvider(widget.ownerId))
          .saveName(text);
      if (mounted) {
        setState(() {
          _saving = false;
        });
        if (Navigator.of(context).canPop()) {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final currentCharactersCount = _controller.text.characters.length;
    final isCountExceeded = currentCharactersCount > 30;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.assistantNameTitle, style: BuilderType.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Character live preview (F09-V02)
              const Center(
                child: BuilderCharacter(size: 96, mood: CharacterMood.idle),
              ),
              const SizedBox(height: 16),
              Text(
                s.assistantNameSubtitle,
                style: BuilderType.body.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Draft text input field (F09-04)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.assistantNameFieldLabel, style: BuilderType.title),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('assistant.nameField'),
                    controller: _controller,
                    maxLength:
                        35, // Soft buffer to allow viewing exceeding graphemes
                    onChanged: (val) {
                      setState(() {
                        _validate(val, s);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: s.assistantNameFieldHint,
                      errorText: _error,
                      counterText: '$currentCharactersCount / 30',
                      counterStyle: TextStyle(
                        color: isCountExceeded
                            ? BuilderColors.warning
                            : BuilderColors.inkSecondary,
                        fontWeight: isCountExceeded
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Action buttons (Save commits version, Cancel discards)
              Row(
                children: [
                  Expanded(
                    child: BuilderButton(
                      key: const Key('assistant.nameSaveBtn'),
                      label: 'Сохранить',
                      loading: _saving,
                      onPressed:
                          (_controller.text.trim().isEmpty || isCountExceeded)
                          ? null
                          : _handleSave,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BuilderButton(
                      key: const Key('assistant.nameCancelBtn'),
                      label: 'Отмена',
                      variant: BuilderButtonVariant.secondary,
                      onPressed: _saving ? null : () => context.pop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
