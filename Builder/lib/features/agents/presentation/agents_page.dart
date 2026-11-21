import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../agents_providers.dart';
import '../domain/lab_agent.dart';
import '../infrastructure/agents_cache.dart';
import '../infrastructure/agents_repository.dart';

String agentError(AppLocalizations s, Object error) => error is LabApiException
    ? switch (error.code) {
        'agents.limit-reached' => s.agentsLimit,
        'session.changed' || 'session.expired' => s.agentsSessionError,
        _ => error.status == 401 ? s.agentsSessionError : s.agentsError,
      }
    : s.agentsError;

class AgentsPage extends ConsumerStatefulWidget {
  const AgentsPage({super.key, required this.ownerId});
  final String ownerId;
  @override
  ConsumerState<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends ConsumerState<AgentsPage> {
  bool _busy = false;

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(agentError(AppLocalizations.of(context), error)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(LabAgent agent, String action) async {
    final s = AppLocalizations.of(context);
    final controller = ref.read(agentsProvider(widget.ownerId).notifier);
    if (action == 'reset' || action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(action == 'reset' ? s.agentsReset : s.agentsDelete),
          content: Text(
            action == 'reset' ? s.agentsResetBody : s.agentsDeleteBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.agentsCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action == 'reset' ? s.agentsReset : s.agentsDelete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _action(
        () => controller.mutate((repo) async {
          if (action == 'reset') {
            await repo.reset(agent.id);
          } else {
            await repo.delete(agent.id);
          }
        }),
      );
      return;
    }
    if (action == 'copy') {
      await _action(
        () => controller.mutate((repo) async {
          await repo.copy(
            agent,
            s.agentsCopyName(
              agent.name.substring(
                0,
                agent.name.length > 180 ? 180 : agent.name.length,
              ),
            ),
          );
        }),
      );
    } else if (action == 'rename') {
      final name = await showDialog<String>(
        context: context,
        builder: (context) => _RenameDialog(name: agent.name),
      );
      if (name == null || !mounted) return;
      await _action(
        () => controller.mutate((repo) async {
          await repo.update(agent.id, {'name': name});
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final value = ref.watch(agentsProvider(widget.ownerId));
    final selected = ref
        .watch(currentAgentIdProvider(widget.ownerId))
        .asData
        ?.value;
    final snapshot = value.asData?.value;
    final enabled = !_busy && snapshot != null && !snapshot.offline;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.agentsTitle),
        actions: [
          IconButton(
            tooltip: s.agentsRefresh,
            onPressed: _busy
                ? null
                : () => ref
                      .read(agentsProvider(widget.ownerId).notifier)
                      .refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(agentError(s, error)),
                TextButton(
                  onPressed: () => ref
                      .read(agentsProvider(widget.ownerId).notifier)
                      .refresh(),
                  child: Text(s.agentsRefresh),
                ),
              ],
            ),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () =>
              ref.read(agentsProvider(widget.ownerId).notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(s.agentsCount(data.agents.length), style: BuilderType.h2),
              const SizedBox(height: 12),
              if (data.offline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(s.agentsOffline),
                ),
              if (data.agents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(s.agentsEmpty),
                ),
              for (final agent in data.agents)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BuilderCard(
                    selected: selected == agent.id,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(agent.name, style: BuilderType.h2),
                            ),
                            PopupMenuButton<String>(
                              key: ValueKey('agent-menu-${agent.id}'),
                              enabled: enabled,
                              onSelected: (action) => _menu(agent, action),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(s.agentsRename),
                                ),
                                PopupMenuItem(
                                  value: 'copy',
                                  child: Text(s.agentsCopy),
                                ),
                                PopupMenuItem(
                                  value: 'reset',
                                  child: Text(s.agentsReset),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(s.agentsDelete),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          agent.taskType == 'prepare_tasks'
                              ? s.agentsPrepareTasks
                              : s.agentsCustomTask,
                        ),
                        if (agent.subject.isNotEmpty || agent.grade.isNotEmpty)
                          Text(
                            [
                              agent.subject,
                              agent.grade,
                            ].where((text) => text.isNotEmpty).join(' · '),
                          ),
                        if (agent.updatedAt != null)
                          Text(
                            s.agentsUpdated(
                              DateFormat.yMd(
                                Localizations.localeOf(context).languageCode,
                              ).add_Hm().format(agent.updatedAt!.toLocal()),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              key: ValueKey('agent-chat-${agent.id}'),
                              style: FilledButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await ref
                                          .read(
                                            currentAgentIdProvider(
                                              widget.ownerId,
                                            ).notifier,
                                          )
                                          .select(agent.id);
                                      if (context.mounted) {
                                        context.push(
                                          '/agents/${Uri.encodeComponent(agent.id)}/chat',
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.chat_bubble_outline),
                              label: const Text('Диалог'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await ref
                                          .read(
                                            currentAgentIdProvider(
                                              widget.ownerId,
                                            ).notifier,
                                          )
                                          .select(agent.id);
                                      if (context.mounted) {
                                        context.push(
                                          '/agents/${Uri.encodeComponent(agent.id)}',
                                        );
                                      }
                                    },
                              child: Text(s.agentsOpen),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (data.agents.length >= 5) Text(s.agentsLimit),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: enabled && data.agents.length < 5
                    ? () => context.push('/agents/new')
                    : null,
                icon: const Icon(Icons.add),
                label: Text(s.agentsCreate),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});
  final String name;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.name);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.agentsRename),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _name,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(labelText: s.agentsName),
          validator: (value) => value!.trim().isEmpty ? s.agentsRequired : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.agentsCancel),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _name.text.trim());
            }
          },
          child: Text(s.agentsSave),
        ),
      ],
    );
  }
}

class AgentEditorPage extends ConsumerStatefulWidget {
  const AgentEditorPage({super.key, required this.ownerId, this.agentId});
  final String ownerId;
  final String? agentId;
  @override
  ConsumerState<AgentEditorPage> createState() => _AgentEditorPageState();
}

class _AgentEditorPageState extends ConsumerState<AgentEditorPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _instruction = TextEditingController();
  bool _busy = false;
  bool _initialized = false;
  bool _draftReady = false;
  int _epoch = 0;
  int _version = 0;
  AgentsCache? _cache;
  Future<void> _draftWrite = Future.value();
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _instruction]) {
      controller.addListener(_persistDraft);
    }
  }

  void _persistDraft() {
    if (!_draftReady || _busy) return;
    final cache = _cache;
    if (cache == null) return;
    final draft = <String, dynamic>{
      'name': _name.text,
      'instruction': _instruction.text,
      'version': _version,
    };
    _draftWrite = _draftWrite
        .then(
          (_) => cache.saveDraft(widget.agentId ?? '__new__', _epoch, draft),
        )
        .catchError((Object _) {
          if (mounted) {
            setState(() => _error = AppLocalizations.of(context).agentsError);
          }
        });
  }

  Future<void> _restoreDraft() async {
    try {
      final draft = await _cache!.readDraft(
        widget.agentId ?? '__new__',
        _epoch,
      );
      if (!mounted) return;
      if (draft != null && draft['version'] == _version) {
        _name.text = draft['name'] as String;
        _instruction.text = draft['instruction'] as String;
      }
    } catch (_) {
      if (mounted) _error = AppLocalizations.of(context).agentsError;
    } finally {
      if (mounted) setState(() => _draftReady = true);
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _instruction]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final s = AppLocalizations.of(context);
    if (_instruction.text.runes.length > 5000) {
      setState(() => _error = s.agentsInstructionLimit);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'instruction': _instruction.text,
      };
      final LabAgent agent = await ref
          .read(agentsProvider(widget.ownerId).notifier)
          .mutate((AgentsRepository repo) {
            if (widget.agentId != null) {
              return repo.update(widget.agentId!, data);
            }
            return repo.create(data);
          });
      if (!mounted) return;
      await _draftWrite;
      await _cache!.saveDraft(widget.agentId ?? '__new__', _epoch, null);
      if (!mounted) return;
      await ref
          .read(currentAgentIdProvider(widget.ownerId).notifier)
          .select(agent.id);
      if (mounted) context.go('/agents');
    } catch (error) {
      if (mounted) setState(() => _error = agentError(s, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final state = ref.watch(agentsProvider(widget.ownerId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.agentId == null ? s.agentsCreate : s.agentsInstruction,
        ),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(agentError(s, error))),
        data: (snapshot) {
          final agent = snapshot.agents
              .where((agent) => agent.id == widget.agentId)
              .firstOrNull;
          if (widget.agentId != null && agent == null) {
            return Center(child: Text(s.unavailableTitle));
          }
          if (!_initialized) {
            _initialized = true;
            _epoch = agent?.epoch ?? 0;
            _version = agent?.version ?? 0;
            _cache = ref.read(agentsRepositoryProvider(widget.ownerId)).cache;
            _name.text = agent?.name ?? '';
            _instruction.text = agent?.instruction ?? '';
            Future.microtask(_restoreDraft);
          }
          final enabled = !_busy && !snapshot.offline && _draftReady;
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (snapshot.offline) ...[
                  Text(s.agentsOffline),
                  const SizedBox(height: BuilderSpace.md),
                ],
                if (agent != null) ...[
                  Text(s.agentsVersion(agent.version), style: BuilderType.h2),
                  const SizedBox(height: BuilderSpace.md),
                ],
                TextFormField(
                  key: const ValueKey('agent-name'),
                  controller: _name,
                  enabled: enabled,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: s.agentsName),
                  validator: (value) =>
                      value!.trim().isEmpty ? s.agentsRequired : null,
                ),
                const SizedBox(height: BuilderSpace.xs),
                TextFormField(
                  key: const ValueKey('agent-instruction'),
                  controller: _instruction,
                  enabled: enabled,
                  minLines: 6,
                  maxLines: 16,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: s.agentsInstruction,
                    counterText: '${_instruction.text.runes.length} / 5 000',
                  ),
                  validator: (value) {
                    if (value!.trim().isEmpty) return s.agentsRequired;
                    return value.runes.length > 5000
                        ? s.agentsInstructionLimit
                        : null;
                  },
                ),
                const SizedBox(height: BuilderSpace.lg),
                FilledButton(
                  onPressed:
                      enabled && (agent != null || snapshot.agents.length < 5)
                      ? _save
                      : null,
                  child: Text(agent == null ? s.agentsCreate : s.agentsSave),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          );
        },
      ),
    );
  }
}
