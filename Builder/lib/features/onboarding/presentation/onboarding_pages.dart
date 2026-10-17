import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/presentation/foundation_pages.dart';
import '../../../ui_kit/ui_kit.dart';
import '../../policy/policy_providers.dart';
import '../application/onboarding_controller.dart';
import '../domain/assistant_setup.dart';
import 'd02_consent_sheet.dart';
import 'onboarding_labels.dart';

class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({
    super.key,
    required this.step,
    required this.child,
    required this.action,
  });
  final int step;
  final Widget child;
  final Widget action;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.appTitle),
        actions: const [LanguageSelector()],
        leading: step == 1
            ? null
            : BackButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(
                      step == 3 ? '/onboarding/preferences' : '/onboarding',
                    );
                  }
                },
              ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(s.onbStep(step, 3), style: BuilderType.small),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: step / 3,
                        backgroundColor: BuilderColors.primaryTint,
                        semanticsLabel: s.onbStep(step, 3),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(24),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        chipTheme: ChipThemeData(
                          backgroundColor: Colors.white,
                          selectedColor: BuilderColors.primaryTint,
                          secondarySelectedColor: BuilderColors.primaryTint,
                          side: const BorderSide(color: BuilderColors.line),
                          shape: const StadiumBorder(),
                          labelStyle: BuilderType.body,
                          secondaryLabelStyle: BuilderType.body,
                          checkmarkColor: BuilderColors.primary,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: SizedBox(width: double.infinity, child: action),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return OnboardingFrame(
      step: 1,
      action: BuilderButton(
        label: s.onbStart,
        onPressed: () => context.push('/onboarding/preferences'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(),
          const SizedBox(height: 20),
          Text(s.onbWelcomeTitle, style: BuilderType.h1),
          const SizedBox(height: 12),
          Text(s.onbWelcomeBody),
          const SizedBox(height: 24),
          _Benefit(BuilderGlyph.doc, s.onbBenefitWork, s.onbBenefitWorkBody),
          const SizedBox(height: 12),
          _Benefit(
            BuilderGlyph.code,
            s.onbBenefitUnderstand,
            s.onbBenefitUnderstandBody,
          ),
          const SizedBox(height: 12),
          _Benefit(
            BuilderGlyph.lock,
            s.onbBenefitControl,
            s.onbBenefitControlBody,
          ),
        ],
      ),
    );
  }
}

class OnboardingPreferencesPage extends ConsumerStatefulWidget {
  const OnboardingPreferencesPage({super.key, required this.ownerId});
  final String ownerId;
  @override
  ConsumerState<OnboardingPreferencesPage> createState() => _PreferencesState();
}

class _PreferencesState extends ConsumerState<OnboardingPreferencesPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final state = ref.watch(onboardingControllerProvider(widget.ownerId));
    final controller = ref.read(
      onboardingControllerProvider(widget.ownerId).notifier,
    );
    final draft = state.draft;
    final subjects = SchoolSubject.values
        .where(
          (subject) =>
              subject == SchoolSubject.other ||
              subjectLabel(
                subject,
                s,
              ).toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();
    return OnboardingFrame(
      step: 2,
      action: BuilderButton(
        label: s.onbNext,
        onPressed: !draft.preferencesValid
            ? null
            : () {
                FocusScope.of(context).unfocus();
                controller.suggestName(
                  s.onbDefaultName(setupSubject(draft, s)),
                );
                context.push('/onboarding/assistant');
              },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.onbPreferencesTitle, style: BuilderType.h1),
          const SizedBox(height: 24),
          Text(s.onbSubject, style: BuilderType.h3),
          const SizedBox(height: 12),
          TextField(
            key: const Key('onb.search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              labelText: s.onbSearchSubject,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final subject in subjects)
                ChoiceChip(
                  key: Key('onb.subject.${subject.name}'),
                  label: Text(subjectLabel(subject, s)),
                  selected: draft.subject == subject,
                  onSelected: (_) => controller.chooseSubject(subject),
                ),
            ],
          ),
          if (subjects.length == 1 &&
              subjects.single == SchoolSubject.other) ...[
            const SizedBox(height: 8),
            Text(s.onbNoSubjects),
          ],
          if (draft.subject == SchoolSubject.other) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('onb.customSubject'),
              initialValue: draft.customSubject,
              onChanged: controller.setCustomSubject,
              decoration: InputDecoration(labelText: s.onbOtherSubject),
            ),
          ],
          const SizedBox(height: 24),
          Text(s.onbGrades, style: BuilderType.h3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final group in const [(1, 4), (5, 7), (8, 9), (10, 11)])
                FilterChip(
                  key: Key('onb.group.${group.$1}'),
                  label: Text('${group.$1}–${group.$2}'),
                  selected: [
                    for (var grade = group.$1; grade <= group.$2; grade++)
                      grade,
                  ].every(draft.grades.contains),
                  onSelected: (_) =>
                      controller.toggleGradeGroup(group.$1, group.$2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var grade = 1; grade <= 11; grade++)
                Semantics(
                  label: s.onbGradeLabel(grade),
                  child: FilterChip(
                    key: Key('onb.grade.$grade'),
                    label: Text('$grade'),
                    selected: draft.grades.contains(grade),
                    onSelected: (_) => controller.toggleGrade(grade),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(s.onbAssistantLanguage, style: BuilderType.h3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final language in AssistantLanguage.values)
                ChoiceChip(
                  key: Key('onb.language.${language.name}'),
                  label: Text(languageLabel(language, s)),
                  selected: draft.language == language,
                  onSelected: (_) => controller.setLanguage(language),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SetupSummary(draft: draft),
          const SizedBox(height: 12),
          Text(s.onbCanChange, style: BuilderType.small),
        ],
      ),
    );
  }
}

class OnboardingAssistantPage extends ConsumerWidget {
  const OnboardingAssistantPage({super.key, required this.ownerId});
  final String ownerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final state = ref.watch(onboardingControllerProvider(ownerId));
    final controller = ref.read(onboardingControllerProvider(ownerId).notifier);
    final available = ref.watch(initialWorkspaceRepositoryProvider).isAvailable;
    return OnboardingFrame(
      step: 3,
      action: BuilderButton(
        label: s.onbCreate,
        loading: state.saving,
        loadingLabel: s.onbCreating,
        onPressed: available && state.draft.ready && !state.saving
            ? () async {
                final policyRepo = ref.read(policyRepositoryProvider);
                final acknowledged = await policyRepo.isPolicyAcknowledged(
                  ownerId: ownerId,
                  policyId: 'd02_cross_border_transfer',
                );
                if (!context.mounted) return;
                if (!acknowledged) {
                  final result = await showD02ConsentSheet(context);
                  if (result == null) return;
                  if (result) {
                    await policyRepo.acknowledgePolicy(
                      ownerId: ownerId,
                      policyId: 'd02_cross_border_transfer',
                      policyVersion: 'v1.0',
                    );
                  }
                }
                await controller.create();
              }
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.onbMeetTitle, style: BuilderType.h1),
          const SizedBox(height: 24),
          _Hero(),
          const SizedBox(height: 20),
          Text(s.onbMeetBody),
          const SizedBox(height: 24),
          TextFormField(
            key: const Key('onb.name'),
            initialValue: state.draft.name,
            enabled: !state.saving,
            onChanged: controller.setName,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: s.onbName),
          ),
          const SizedBox(height: 20),
          SetupSummary(draft: state.draft),
          const SizedBox(height: 12),
          Text(s.onbLocalOnly, style: BuilderType.small),
          if (!available) ...[
            const SizedBox(height: 16),
            BuilderCard(child: Text(s.onbStorageUnavailable)),
          ],
          if (state.failure != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: BuilderCard(
                child: Text(switch (state.failure!) {
                  OnboardingFailure.unavailable => s.onbStorageUnavailable,
                  OnboardingFailure.invalidDraft => s.onbInvalidDraft,
                  OnboardingFailure.saveFailed => s.onbSaveError,
                  OnboardingFailure.sessionChanged => s.onbSessionChanged,
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SetupSummary extends StatelessWidget {
  const SetupSummary({super.key, required this.draft});
  final AssistantSetup draft;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final grades = draft.grades.toList()..sort();
    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.onbSummaryTitle, style: BuilderType.title),
          const SizedBox(height: 8),
          Text(setupSubject(draft, s)),
          Text(
            grades.isEmpty
                ? s.onbChooseGrades
                : '${s.onbGrades}: ${grades.join(', ')}',
          ),
          Text(
            '${s.onbAssistantLanguage}: ${languageLabel(draft.language, s)}',
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: AppLocalizations.of(context).onbHeroLabel,
    child: const ExcludeSemantics(
      child: Center(child: BuilderCharacter(size: 148)),
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.title, this.body);
  final BuilderGlyph icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => BuilderCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuilderIconTile(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BuilderType.title),
              const SizedBox(height: 4),
              Text(body),
            ],
          ),
        ),
      ],
    ),
  );
}
