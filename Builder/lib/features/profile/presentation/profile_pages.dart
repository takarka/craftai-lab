import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/providers.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../ui_kit/ui_kit.dart';
import '../../onboarding/domain/assistant_setup.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/domain/initial_workspace_repository.dart';
import '../../onboarding/presentation/onboarding_labels.dart';
import '../../session/infrastructure/persistent_session_repository.dart';
import '../../tools/domain/tool_definition.dart';
import '../../tools/presentation/d07_os_permission_dialog.dart';
import '../domain/profile.dart';
import '../infrastructure/reminder_service.dart';
import '../profile_providers.dart';
import 'profile_strings.dart';

// Kept in sync with pubspec.yaml; builds may supply APP_VERSION.
const profileAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0+1',
);

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.ownerId});
  final String ownerId;
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final s = ProfileStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.logoutTitle),
        content: Text(s.logoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            key: const Key('profile.confirmLogout'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.logout),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _signingOut) return;
    setState(() => _signingOut = true);
    try {
      final session = ref.read(sessionRepositoryProvider);
      if (session is! PersistentSessionRepository) {
        throw StateError('Sign out unavailable');
      }
      try {
        await ref.read(authGatewayProvider).logout();
      } finally {
        // Always close the local workspace and return to sign-in, including a
        // network failure while revoking the server-side refresh token.
        await session.signOut();
      }
    } catch (_) {
      if (mounted) _showMessage(context, s.failed);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(context);
    final account = ref.watch(profileAccountProvider(widget.ownerId));
    final preferences = ref.watch(teacherPreferencesProvider(widget.ownerId));
    final snapshot = account.asData?.value.snapshot;
    return _ProfileScaffold(
      title: s.title,
      children: [
        BuilderCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BuilderIconTile(BuilderGlyph.profile, size: 48),
                  const SizedBox(width: BuilderSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot?.name?.trim().isNotEmpty == true
                              ? snapshot!.name!
                              : s.account,
                          style: BuilderType.h3,
                        ),
                        if (snapshot?.email?.isNotEmpty == true) ...[
                          const SizedBox(height: BuilderSpace.xxs),
                          Text(snapshot!.email!, style: BuilderType.small),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('profile.edit'),
                    tooltip: s.edit,
                    onPressed: () => context.push('/profile/settings'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: BuilderSpace.md),
              preferences.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) =>
                    Text(s.preferencesError, style: BuilderType.small),
                data: (value) => value == null
                    ? Text(s.preferencesMissing, style: BuilderType.small)
                    : Wrap(
                        spacing: BuilderSpace.xs,
                        runSpacing: BuilderSpace.xs,
                        children: [
                          BuilderBadge(
                            setupSubject(
                              value.setup,
                              AppLocalizations.of(context),
                            ),
                          ),
                          if (value.setup.grades.isNotEmpty)
                            BuilderBadge(
                              '${(value.setup.grades.toList()..sort()).join(', ')} · ${s.grades.toLowerCase()}',
                              neutral: true,
                            ),
                        ],
                      ),
              ),
              if (account.asData?.value.unavailable == true &&
                  snapshot == null) ...[
                const SizedBox(height: BuilderSpace.xs),
                Text(s.accountUnavailable, style: BuilderType.small),
              ],
            ],
          ),
        ),
        _UsageCard(ownerId: widget.ownerId),
        BuilderCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ProfileLink(
                key: const Key('profile.settings'),
                icon: BuilderGlyph.settings,
                title: s.settings,
                subtitle: s.settingsSubtitle,
                onTap: () => context.push('/profile/settings'),
              ),
              const Divider(height: 1, indent: 72, endIndent: 16),
              _ProfileLink(
                key: const Key('profile.privacy'),
                icon: BuilderGlyph.lock,
                title: s.privacy,
                subtitle: s.privacySubtitle,
                onTap: () => context.push('/profile/privacy'),
              ),
              const Divider(height: 1, indent: 72, endIndent: 16),
              _ProfileLink(
                key: const Key('profile.help'),
                icon: BuilderGlyph.info,
                title: s.help,
                subtitle: s.helpSubtitle,
                onTap: () => context.push('/profile/help'),
              ),
            ],
          ),
        ),
        TextButton.icon(
          key: const Key('profile.logout'),
          onPressed: _signingOut ? null : _signOut,
          style: TextButton.styleFrom(
            foregroundColor: BuilderColors.warning,
            minimumSize: const Size(48, 48),
          ),
          icon: _signingOut
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout, size: 18),
          label: Text(s.logout, textAlign: TextAlign.center),
        ),
        const Text(
          'Craft Builder · $profileAppVersion',
          style: BuilderType.small,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _UsageCard extends ConsumerWidget {
  const _UsageCard({required this.ownerId});
  final String ownerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ProfileStrings.of(context);
    final value = ref.watch(profileAccountProvider(ownerId));
    final canRefresh = ref.watch(profileAccountGatewayProvider).isAvailable;
    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIconTile(BuilderGlyph.bolt),
              const SizedBox(width: BuilderSpace.sm),
              Expanded(child: Text(s.usage, style: BuilderType.title)),
              if (canRefresh)
                IconButton(
                  tooltip: s.refresh,
                  onPressed: value.isLoading
                      ? null
                      : () => ref.invalidate(profileAccountProvider(ownerId)),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
          const SizedBox(height: BuilderSpace.md),
          value.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text(s.usageUnavailable, style: BuilderType.body),
            data: (state) {
              final data = state.snapshot;
              final tokens = data?.usedTokens;
              final locale = Localizations.localeOf(context).languageCode;
              final number = NumberFormat.decimalPattern(locale);
              final date = DateFormat('d MMM y, HH:mm', locale);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tokens == null) ...[
                    Text(s.usageUnavailable, style: BuilderType.body),
                    const SizedBox(height: BuilderSpace.xxs),
                    Text(s.usageExplanation, style: BuilderType.small),
                  ] else ...[
                    Text(number.format(tokens), style: BuilderType.h1),
                    Text(s.used, style: BuilderType.small),
                    if (data!.periodStartUtc != null &&
                        data.periodEndUtc != null) ...[
                      const SizedBox(height: BuilderSpace.xs),
                      Text(
                        '${DateFormat.yMMMd(locale).format(data.periodStartUtc!.toLocal())} — '
                        '${DateFormat.yMMMd(locale).format(data.periodEndUtc!.toLocal())}',
                        style: BuilderType.small,
                      ),
                    ],
                    if (data.tokenLimit != null) ...[
                      const SizedBox(height: BuilderSpace.sm),
                      LinearProgressIndicator(
                        value: (tokens / data.tokenLimit!).clamp(0.0, 1.0),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(
                          BuilderRadii.control,
                        ),
                        backgroundColor: BuilderColors.primaryTint,
                        semanticsLabel: s.usage,
                        semanticsValue:
                            '${number.format(tokens)} / ${number.format(data.tokenLimit)}',
                      ),
                      const SizedBox(height: BuilderSpace.xs),
                      Text(
                        '${number.format(tokens)} / ${number.format(data.tokenLimit)}',
                        style: BuilderType.small,
                      ),
                    ],
                  ],
                  if (data != null) ...[
                    const SizedBox(height: BuilderSpace.sm),
                    Text(
                      '${state.cached ? s.cached : s.refresh}: ${date.format(data.updatedAtUtc.toLocal())}',
                      style: BuilderType.small,
                    ),
                  ],
                  if (state.unavailable && state.cached) ...[
                    const SizedBox(height: BuilderSpace.xs),
                    Text(
                      s.updateFailed,
                      style: BuilderType.small.copyWith(
                        color: BuilderColors.warning,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ProfileSettingsPage extends ConsumerWidget {
  const ProfileSettingsPage({super.key, required this.ownerId});
  final String ownerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ProfileStrings.of(context);
    final preferences = ref.watch(teacherPreferencesProvider(ownerId));
    return _ProfileScaffold(
      title: s.settings,
      children: [
        preferences.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => BuilderCard(
            child: Column(
              children: [
                Text(s.preferencesError),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(teacherPreferencesProvider(ownerId)),
                  child: Text(s.refresh),
                ),
              ],
            ),
          ),
          data: (value) => value == null
              ? BuilderCard(child: Text(s.preferencesMissing))
              : _PreferencesForm(
                  key: ValueKey(ownerId),
                  ownerId: ownerId,
                  initial: value,
                ),
        ),
        const _RemindersCard(),
        _InfoCard(
          title: s.about,
          body: 'Craft Builder · $profileAppVersion\n\n${s.localStorage}',
        ),
      ],
    );
  }
}

class _PreferencesForm extends ConsumerStatefulWidget {
  const _PreferencesForm({
    super.key,
    required this.ownerId,
    required this.initial,
  });
  final String ownerId;
  final TeacherPreferences initial;
  @override
  ConsumerState<_PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends ConsumerState<_PreferencesForm> {
  final _form = GlobalKey<FormState>();
  late AssistantSetup _setup;
  late String _language;
  late final TextEditingController _customSubject;
  bool _saving = false;
  bool _gradesInvalid = false;
  @override
  void initState() {
    super.initState();
    _setup = widget.initial.setup;
    _language = widget.initial.uiLanguage;
    _customSubject = TextEditingController(text: _setup.customSubject);
  }

  @override
  void dispose() {
    _customSubject.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final valid = _form.currentState!.validate();
    setState(() => _gradesInvalid = _setup.grades.isEmpty);
    if (!valid || _gradesInvalid) return;
    final s = ProfileStrings.of(context);
    final store = ref.read(profileStoreProvider);
    if (store == null) {
      _showMessage(context, s.failed);
      return;
    }
    setState(() => _saving = true);
    try {
      await store.savePreferences(
        permit: WorkspaceWritePermit(
          ownerId: widget.ownerId,
          canCommit: () =>
              mounted &&
              isProfileOwner(
                ref.read(sessionProvider).asData?.value,
                widget.ownerId,
              ),
        ),
        setup: _setup.copyWith(customSubject: _customSubject.text),
        uiLanguage: _language,
      );
      if (!mounted) return;
      ref.read(appLocaleProvider.notifier).select(Locale(_language));
      ref.invalidate(teacherPreferencesProvider(widget.ownerId));
      _showMessage(context, ProfileStrings.of(context).saved);
    } catch (_) {
      if (mounted) _showMessage(context, s.failed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(context);
    final labels = AppLocalizations.of(context);
    return BuilderCard(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.uiLanguage, style: BuilderType.title),
            const SizedBox(height: BuilderSpace.sm),
            DropdownButtonFormField<String>(
              key: const Key('profile.uiLanguage'),
              initialValue: const ['ru', 'kk'].contains(_language)
                  ? _language
                  : 'ru',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _language = value!),
            ),
            const SizedBox(height: BuilderSpace.xs),
            Text(s.languageExplanation, style: BuilderType.small),
            const SizedBox(height: BuilderSpace.xl),
            Text(s.teaching, style: BuilderType.title),
            const SizedBox(height: BuilderSpace.sm),
            DropdownButtonFormField<SchoolSubject>(
              key: const Key('profile.subject'),
              initialValue: _setup.subject,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.subject),
              items: SchoolSubject.values
                  .map(
                    (subject) => DropdownMenuItem(
                      value: subject,
                      child: Text(subjectLabel(subject, labels)),
                    ),
                  )
                  .toList(),
              validator: (value) => value == null ? s.preferencesMissing : null,
              onChanged: _saving
                  ? null
                  : (value) => setState(
                      () => _setup = _setup.copyWith(subject: value),
                    ),
            ),
            if (_setup.subject == SchoolSubject.other) ...[
              const SizedBox(height: BuilderSpace.sm),
              TextFormField(
                key: const Key('profile.customSubject'),
                controller: _customSubject,
                enabled: !_saving,
                maxLength: 100,
                decoration: InputDecoration(labelText: s.customSubject),
                validator: (value) => value == null || value.trim().isEmpty
                    ? s.customSubject
                    : null,
              ),
            ],
            const SizedBox(height: BuilderSpace.md),
            Text(s.grades, style: BuilderType.small),
            const SizedBox(height: BuilderSpace.xs),
            Wrap(
              spacing: BuilderSpace.xs,
              runSpacing: BuilderSpace.xxs,
              children: [
                for (var grade = 1; grade <= 11; grade++)
                  FilterChip(
                    key: Key('profile.grade.$grade'),
                    label: Text('$grade'),
                    tooltip: '${s.grades}: $grade',
                    selected: _setup.grades.contains(grade),
                    selectedColor: BuilderColors.primaryTint,
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                            final grades = {..._setup.grades};
                            if (selected) {
                              grades.add(grade);
                            } else {
                              grades.remove(grade);
                            }
                            _setup = _setup.copyWith(grades: grades);
                            _gradesInvalid = grades.isEmpty;
                          }),
                  ),
              ],
            ),
            if (_gradesInvalid)
              Text(
                s.chooseGrades,
                style: BuilderType.small.copyWith(color: BuilderColors.warning),
              ),
            const SizedBox(height: BuilderSpace.lg),
            BuilderButton(
              key: const Key('profile.savePreferences'),
              label: s.save,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _RemindersCard extends ConsumerWidget {
  const _RemindersCard();

  static const _notificationToolDef = ToolDefinition(
    name: 'system.notifications',
    displayName: 'Системные уведомления',
    description: 'Отправка локальных напоминаний о графике курса',
    category: ToolCategory.calendar,
    capability: ToolCapability.requiresConfirmation,
    defaultOsPermission: OsPermissionStatus.notRequested,
    parametersSchema: {},
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ProfileStrings.of(context);
    final isKk = Localizations.localeOf(context).languageCode == 'kk';
    final reminderState = ref.watch(reminderServiceProvider);
    final notifier = ref.read(reminderServiceProvider.notifier);

    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIconTile(BuilderGlyph.calendar),
              const SizedBox(width: BuilderSpace.sm),
              Expanded(child: Text(s.reminders, style: BuilderType.title)),
            ],
          ),
          const SizedBox(height: BuilderSpace.xs),
          Text(s.remindersDescription, style: BuilderType.body),
          const SizedBox(height: BuilderSpace.md),
          DropdownButtonFormField<ReminderFrequency>(
            key: const Key('profile.remindersDropdown'),
            initialValue: reminderState.frequency,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: s.reminders,
            ),
            items: ReminderFrequency.values
                .map(
                  (freq) => DropdownMenuItem(
                    value: freq,
                    child: Text(freq.label(isKk)),
                  ),
                )
                .toList(),
            onChanged: (newFreq) async {
              if (newFreq == null) return;
              if (newFreq == ReminderFrequency.disabled) {
                notifier.cancelAll();
                _showMessage(context, s.remindersCancelled);
                return;
              }

              if (!reminderState.hasPermission) {
                final granted = await D07OsPermissionDialog.show(
                  context,
                  tool: _notificationToolDef,
                );
                if (granted == true) {
                  notifier.setPermissionStatus(OsPermissionStatus.granted);
                  notifier.setFrequency(newFreq);
                  if (context.mounted) {
                    _showMessage(context, s.remindersSaved);
                  }
                } else {
                  notifier.setPermissionStatus(OsPermissionStatus.denied);
                  if (context.mounted) {
                    _showMessage(context, s.remindersPermissionRequired);
                  }
                }
              } else {
                notifier.setFrequency(newFreq);
                _showMessage(context, s.remindersSaved);
              }
            },
          ),
          if (reminderState.frequency != ReminderFrequency.disabled) ...[
            const SizedBox(height: BuilderSpace.xs),
            Text(
              reminderState.frequency.schedule(isKk),
              style: BuilderType.small.copyWith(color: BuilderColors.primary),
            ),
          ],
          if (reminderState.scheduledReminders.isNotEmpty) ...[
            const SizedBox(height: BuilderSpace.sm),
            Column(
              key: const Key('profile.scheduledRemindersList'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final rem in reminderState.scheduledReminders) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.alarm, size: 16, color: BuilderColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${rem.title} (${rem.scheduledTime})',
                            style: BuilderType.small,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (reminderState.frequency != ReminderFrequency.disabled) ...[
            const SizedBox(height: BuilderSpace.md),
            OutlinedButton.icon(
              key: const Key('profile.cancelAllRemindersBtn'),
              onPressed: () {
                notifier.cancelAll();
                _showMessage(context, s.remindersCancelled);
              },
              icon: const Icon(Icons.notifications_off_outlined, size: 18),
              label: Text(s.remindersCancelAll),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfilePrivacyPage extends StatelessWidget {
  const ProfilePrivacyPage({super.key, this.ownerId});
  final String? ownerId;

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(context);
    return _ProfileScaffold(
      title: s.privacy,
      children: [
        Text(s.dataMap, style: BuilderType.h3),
        _InfoCard(
          title: s.device,
          body: s.deviceData,
          icon: BuilderGlyph.phone,
        ),
        _InfoCard(
          title: 'CraftAI',
          body: s.craftData,
          icon: BuilderGlyph.cloud,
        ),
        _InfoCard(title: s.cloud, body: s.cloudData, icon: BuilderGlyph.globe),
        _InfoCard(title: s.safety, body: s.safetyBody, icon: BuilderGlyph.lock),
        TextButton.icon(
          key: const Key('profile.privacyPolicy'),
          onPressed: () => context.push('/legal/privacy'),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(s.policy),
        ),
        Text(s.assistantDataOwner, style: BuilderType.small),
        _AccountDeletionCard(ownerId: ownerId),
      ],
    );
  }
}

class _AccountDeletionCard extends ConsumerStatefulWidget {
  const _AccountDeletionCard({this.ownerId});
  final String? ownerId;

  @override
  ConsumerState<_AccountDeletionCard> createState() => _AccountDeletionCardState();
}

class _AccountDeletionCardState extends ConsumerState<_AccountDeletionCard> {
  bool _deleting = false;

  Future<void> _handleDelete() async {
    final s = ProfileStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('profile.deleteAccountDialog'),
        title: Text(s.deleteAccountPrompt),
        content: Text(s.deleteAccountWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            key: const Key('profile.confirmDeleteAccount'),
            style: TextButton.styleFrom(foregroundColor: BuilderColors.warning),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.deleteAccountConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      final gateway = ref.read(profileAccountGatewayProvider);
      if (widget.ownerId != null) {
        await gateway.deleteAccount(widget.ownerId!);
      }
      final session = ref.read(sessionRepositoryProvider);
      if (session is PersistentSessionRepository) {
        await session.signOut();
      }
      await ref.read(workspaceStorageServiceProvider)?.closeActiveWorkspace();
      if (mounted) {
        _showMessage(context, s.deleteAccountSuccess);
        context.go('/');
      }
    } catch (_) {
      if (mounted) {
        _showMessage(context, s.failed);
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(context);
    final gateway = ref.watch(profileAccountGatewayProvider);
    if (!gateway.isAvailable || widget.ownerId == null) {
      return _InfoCard(title: s.deletion, body: s.deletionUnavailable);
    }

    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIconTile(BuilderGlyph.lock),
              const SizedBox(width: BuilderSpace.sm),
              Expanded(child: Text(s.deletion, style: BuilderType.title)),
            ],
          ),
          const SizedBox(height: BuilderSpace.xs),
          Text(s.deleteAccountWarning, style: BuilderType.body),
          const SizedBox(height: BuilderSpace.md),
          TextButton.icon(
            key: const Key('profile.deleteAccountBtn'),
            onPressed: _deleting ? null : _handleDelete,
            style: TextButton.styleFrom(
              foregroundColor: BuilderColors.warning,
            ),
            icon: _deleting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever, size: 18),
            label: Text(s.deleteAccount),
          ),
        ],
      ),
    );
  }
}

class ProfileHelpPage extends StatefulWidget {
  const ProfileHelpPage({super.key});
  @override
  State<ProfileHelpPage> createState() => _ProfileHelpPageState();
}

class _ProfileHelpPageState extends State<ProfileHelpPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(context);
    final query = _query.trim().toLowerCase();
    final items = s.faq
        .where((item) => '${item.question} ${item.answer}'.toLowerCase().contains(query))
        .toList();
    return _ProfileScaffold(
      title: s.help,
      children: [
        TextField(
          key: const Key('profile.helpSearch'),
          decoration: InputDecoration(
            labelText: s.search,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (items.isEmpty) Text(s.noResults, style: BuilderType.body),
        for (final item in items)
          BuilderCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: ValueKey(item.id),
              title: Text(item.question, style: BuilderType.title),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(item.answer, style: BuilderType.body),
                ),
              ],
            ),
          ),
        const _SupportContactCard(),
      ],
    );
  }
}

class _SupportContactCard extends StatelessWidget {
  const _SupportContactCard();

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(context);
    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIconTile(BuilderGlyph.info),
              const SizedBox(width: BuilderSpace.sm),
              Expanded(child: Text(s.support, style: BuilderType.title)),
            ],
          ),
          const SizedBox(height: BuilderSpace.xs),
          Text(s.supportPrivacyNotice, style: BuilderType.body),
          const SizedBox(height: BuilderSpace.xs),
          Text(s.supportSlaNotice, style: BuilderType.small),
          const SizedBox(height: BuilderSpace.md),
          BuilderButton(
            key: const Key('profile.contactSupportBtn'),
            label: s.contactSupport,
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => const _SupportContactSheet(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SupportContactSheet extends StatefulWidget {
  const _SupportContactSheet();

  @override
  State<_SupportContactSheet> createState() => _SupportContactSheetState();
}

class _SupportContactSheetState extends State<_SupportContactSheet> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) return;

    final s = ProfileStrings.of(context);
    setState(() => _sending = true);
    // B06 does not expose a support-submission contract yet. Keep the draft
    // in the sheet and never report success for a message that was not sent.
    setState(() => _sending = false);
    _showMessage(context, s.supportUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(context);
    return Padding(
      key: const Key('profile.supportSheet'),
      padding: EdgeInsets.only(
        left: BuilderSpace.md,
        right: BuilderSpace.md,
        top: BuilderSpace.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + BuilderSpace.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.contactSupport, style: BuilderType.h3),
          const SizedBox(height: BuilderSpace.xs),
          Text(s.supportPrivacyNotice, style: BuilderType.small),
          const SizedBox(height: BuilderSpace.md),
          TextField(
            key: const Key('profile.supportSubject'),
            controller: _subjectController,
            decoration: InputDecoration(
              labelText: s.supportSubject,
            ),
          ),
          const SizedBox(height: BuilderSpace.sm),
          TextField(
            key: const Key('profile.supportMessage'),
            controller: _messageController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: s.supportMessage,
            ),
          ),
          const SizedBox(height: BuilderSpace.md),
          BuilderButton(
            key: const Key('profile.sendSupportBtn'),
            label: s.send,
            loading: _sending,
            onPressed: _sending ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView.separated(
            padding: const EdgeInsets.all(BuilderSpace.md),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: BuilderSpace.md),
            itemBuilder: (_, index) => children[index],
          ),
        ),
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body, this.icon});
  final String title;
  final String body;
  final BuilderGlyph? icon;
  @override
  Widget build(BuildContext context) => BuilderCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          BuilderIconTile(icon!),
          const SizedBox(height: BuilderSpace.sm),
        ],
        Text(title, style: BuilderType.title),
        const SizedBox(height: BuilderSpace.xs),
        Text(body, style: BuilderType.body),
      ],
    ),
  );
}

class _ProfileLink extends StatelessWidget {
  const _ProfileLink({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final BuilderGlyph icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    leading: BuilderIconTile(icon),
    title: Text(title, style: BuilderType.title),
    subtitle: Text(subtitle, style: BuilderType.small),
    trailing: const BuilderIcon(
      BuilderGlyph.chevron,
      size: 18,
      color: BuilderColors.inkDisabled,
    ),
    onTap: onTap,
  );
}

void _showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
