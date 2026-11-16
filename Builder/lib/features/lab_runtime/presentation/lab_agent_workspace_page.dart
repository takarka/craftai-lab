import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/providers.dart';
import '../../../core/network/api_http_client.dart';
import '../../agents/agents_providers.dart';
import '../../agents/domain/lab_agent.dart';
import '../../session/session_providers.dart';
import '../domain/lab_run_models.dart';
import '../infrastructure/lab_runtime_api.dart';
import 'lab_agent_chat_page.dart';
import 'lab_agent_settings_page.dart';
import 'lab_run_controller.dart';
import 'lab_run_trace_page.dart';

final labRuntimeApiProvider = Provider.autoDispose<LabRuntimeApi>((ref) {
  final config = ref.watch(appConfigProvider);
  final baseUri = config?.apiBaseUri ?? Uri.parse('http://127.0.0.1:5001');
  final client = createApiHttpClient(config);
  ref.onDispose(client.close);
  final tokens = ref.watch(secureTokenStorageProvider);
  return HttpLabRuntimeApi(
    client: client,
    baseUri: baseUri,
    getAccessToken: () async {
      var auth = await tokens.readTokens();
      if (auth == null || auth.isExpired) auth = await tokens.refreshTokens();
      return auth?.accessToken;
    },
  );
});

class LabAgentWorkspacePage extends ConsumerStatefulWidget {
  const LabAgentWorkspacePage({
    super.key,
    required this.ownerId,
    required this.agentId,
    this.openSettingsInitially = false,
  });

  final String ownerId;
  final String agentId;
  final bool openSettingsInitially;

  @override
  ConsumerState<LabAgentWorkspacePage> createState() =>
      _LabAgentWorkspacePageState();
}

class _LabAgentWorkspacePageState extends ConsumerState<LabAgentWorkspacePage> {
  List<LabModelInfo> _models = const [];
  bool _modelsLoaded = false;
  bool _openedInitialSettings = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadModels);
  }

  Future<void> _loadModels() async {
    try {
      final api = ref.read(labRuntimeApiProvider);
      final models = await api.listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _modelsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _modelsLoaded = true);
    }
  }

  LabModelInfo _resolveModel(LabAgent agent) {
    final id = agent.modelId;
    if (id != null && id.isNotEmpty) {
      final found = _models.where((m) => m.modelId == id).firstOrNull;
      if (found != null) return found;
      return LabModelInfo(
        modelId: id,
        available: true,
        supportsTools: true,
        supportsVision: true,
      );
    }
    if (_models.isNotEmpty) return _models.first;
    return const LabModelInfo(
      modelId: 'google/gemini-2.5-flash',
      available: true,
      supportsTools: true,
      supportsVision: true,
    );
  }

  Future<LabPickedPhoto?> _pickPhoto() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );
    final file = files.firstOrNull;
    if (file == null) return null;
    final bytes = await file.xFile.readAsBytes();
    return LabPickedPhoto(fileName: file.name, bytes: bytes);
  }

  void _openSettings(LabAgent agent, LabModelInfo currentModel) {
    final api = ref.read(labRuntimeApiProvider);
    final models = _models.isNotEmpty ? _models : <LabModelInfo>[currentModel];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LabAgentSettingsPage(
          agentId: agent.id,
          api: api,
          availableModels: models,
          initialModelId: currentModel.modelId,
          initialInstruction: agent.instruction,
          initialAllowSave: agent.allowSave,
          initialAllowSearch: agent.allowSearch,
          photoPicker: _pickPhoto,
          onSaveCoreSettings:
              ({
                required modelId,
                required instruction,
                required allowSave,
                required allowSearch,
              }) async {
                await ref
                    .read(agentsProvider(widget.ownerId).notifier)
                    .mutate(
                      (repo) => repo.update(agent.id, {
                        if (modelId.isNotEmpty) 'model_id': modelId,
                        'instruction': instruction,
                        'permissions': {
                          'save_material': allowSave,
                          'search_materials': allowSearch,
                        },
                      }),
                    );
              },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final agentsAsync = ref.watch(agentsProvider(widget.ownerId));
    final api = ref.watch(labRuntimeApiProvider);

    return agentsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$err')),
      ),
      data: (snapshot) {
        final agent = snapshot.agents
            .where((a) => a.id == widget.agentId)
            .firstOrNull;
        if (agent == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(s.unavailableTitle)),
          );
        }
        if (!_modelsLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final resolvedModel = _resolveModel(agent);
        if (widget.openSettingsInitially && !_openedInitialSettings) {
          _openedInitialSettings = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openSettings(agent, resolvedModel);
          });
        }
        final controller = LabRunController(
          api: api,
          config: LabAgentRunConfig(
            agentId: agent.id,
            model: resolvedModel,
            allowSave: agent.allowSave,
            allowSearch: agent.allowSearch,
          ),
        );
        return LabAgentChatPage(
          key: ValueKey(
            '${agent.id}-${agent.version}-${resolvedModel.modelId}-${agent.allowSave}-${agent.allowSearch}',
          ),
          agentName: agent.name,
          controller: controller,
          onOpenSettings: () => _openSettings(agent, resolvedModel),
        );
      },
    );
  }
}

class LabRunTraceRoutePage extends ConsumerWidget {
  const LabRunTraceRoutePage({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(labRuntimeApiProvider);
    return LabRunTracePage(runId: runId, api: api);
  }
}
