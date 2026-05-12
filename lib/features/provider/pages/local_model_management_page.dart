import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/model_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/local_litert_model_store.dart';
import '../../../core/services/local_provider_config.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tile_button.dart';

class LocalModelManagementPage extends StatefulWidget {
  const LocalModelManagementPage({
    super.key,
    required this.providerKey,
    required this.providerDisplayName,
  });

  final String providerKey;
  final String providerDisplayName;

  @override
  State<LocalModelManagementPage> createState() =>
      _LocalModelManagementPageState();
}

class _LocalModelManagementPageState extends State<LocalModelManagementPage> {
  bool _discovering = false;
  bool _testing = false;
  bool _importing = false;
  LocalLiteRtImportProgress? _importProgress;
  String? _selectedModelId;

  Future<void> _importNativeModel(ProviderConfig cfg) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final gguf = isLocalGgufProvider(cfg);
    try {
      setState(() {
        _importing = true;
        _importProgress = null;
      });
      final imported = gguf
          ? await LocalLiteRtModelStore.pickAndImportGgufModel(
              onProgress: (progress) {
                if (!mounted) return;
                setState(() => _importProgress = progress);
              },
            )
          : await LocalLiteRtModelStore.pickAndImportModel(
              onProgress: (progress) {
                if (!mounted) return;
                setState(() => _importProgress = progress);
              },
            );
      if (imported == null) return;
      final next = cfg.copyWith(
        baseUrl: imported.path,
        providerType: ProviderKind.openai,
        useResponseApi: false,
        models: [imported.modelId],
        modelOverrides: {
          imported.modelId: _textChatOverride(
            imported.modelId,
            localModelPath: imported.path,
            localRuntime: gguf ? localGgufRuntime : localLiteRtRuntime,
          ),
        },
      );
      await settings.setProviderConfig(widget.providerKey, next);
      if (!mounted) return;
      setState(() => _selectedModelId = imported.modelId);
      _showMessage(l10n.localModelManagementImportSuccess(imported.fileName));
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        l10n.localModelManagementImportFailed(
          _localImportErrorMessage(l10n, e),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importProgress = null;
        });
      }
    }
  }

  Future<void> _discoverModels(ProviderConfig cfg) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    setState(() => _discovering = true);
    try {
      final list = await ProviderManager.listModels(cfg);
      final ids = [
        for (final model in list)
          if (model.id.trim().isNotEmpty) model.id.trim(),
      ];
      if (ids.isEmpty) {
        _showMessage(l10n.localModelManagementNoModelsFound);
        return;
      }
      final overrides = Map<String, dynamic>.from(cfg.modelOverrides);
      for (final id in ids) {
        overrides[id] = overrides[id] ?? _textChatOverride(id);
      }
      await settings.setProviderConfig(
        widget.providerKey,
        cfg.copyWith(models: ids, modelOverrides: overrides),
      );
      if (!mounted) return;
      setState(() => _selectedModelId = ids.first);
      _showMessage(l10n.localModelManagementModelsUpdated(ids.length));
    } catch (e) {
      if (!mounted) return;
      _showMessage(l10n.localModelManagementDiscoverFailed('$e'));
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _testConnection(ProviderConfig cfg) async {
    final l10n = AppLocalizations.of(context)!;
    final modelId =
        _selectedModelId ?? (cfg.models.isEmpty ? null : cfg.models.first);
    if (modelId == null || modelId.trim().isEmpty) {
      _showMessage(l10n.localModelManagementNoModelsFound);
      return;
    }
    setState(() => _testing = true);
    try {
      await ProviderManager.testConnection(cfg, modelId);
      if (!mounted) return;
      _showMessage(l10n.localModelManagementTestSuccess);
    } catch (e) {
      if (!mounted) return;
      _showMessage(l10n.localModelManagementTestFailed('$e'));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _localImportErrorMessage(AppLocalizations l10n, Object error) {
    if (error is LocalLiteRtImportException) {
      return switch (error.error) {
        LocalLiteRtImportError.notLiteRtModel =>
          l10n.addProviderSheetLocalImportNotLiteRt,
        LocalLiteRtImportError.notGgufModel =>
          l10n.addProviderSheetLocalImportNotGguf,
        LocalLiteRtImportError.emptyFile =>
          l10n.addProviderSheetLocalImportEmptyFile,
        LocalLiteRtImportError.unreadableSource =>
          l10n.addProviderSheetLocalImportUnreadable,
      };
    }
    return '$error';
  }

  Map<String, dynamic> _textChatOverride(
    String modelId, {
    String? localModelPath,
    String localRuntime = localLiteRtRuntime,
  }) {
    return {
      'name': modelId,
      'type': 'chat',
      'input': ['text'],
      'output': ['text'],
      if (localModelPath != null) ...{
        'localRuntime': localRuntime,
        'localModelPath': localModelPath,
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final liteRt = isLocalLiteRtProvider(cfg);
    final gguf = isLocalGgufProvider(cfg);
    final nativeModel = liteRt || gguf;
    final selected =
        _selectedModelId ?? (cfg.models.isEmpty ? null : cfg.models.first);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.localModelManagementTitle),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _section(
            children: [
              _infoRow(l10n.providerDetailPageNameLabel, cfg.name),
              _infoRow(
                l10n.localModelManagementModeLabel,
                liteRt
                    ? l10n.localModelManagementLiteRtMode
                    : gguf
                    ? l10n.localModelManagementGgufMode
                    : l10n.localModelManagementOllamaMode,
              ),
              if (nativeModel)
                _fileRow(l10n, localRuntimeModelPath(cfg, selected ?? '')),
              if (!nativeModel)
                _infoRow(l10n.localModelManagementBaseUrlLabel, cfg.baseUrl),
              if (selected != null)
                _infoRow(l10n.localModelManagementModelIdLabel, selected),
            ],
          ),
          const SizedBox(height: 12),
          if (nativeModel) _nativeModelActions(l10n, cfg),
          if (!nativeModel) _ollamaActions(l10n, cfg),
          const SizedBox(height: 12),
          _modelsSection(l10n, cfg, selected),
        ],
      ),
    );
  }

  Widget _nativeModelActions(AppLocalizations l10n, ProviderConfig cfg) {
    return _section(
      children: [
        if (_importing) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: LinearProgressIndicator(value: _importProgress?.fraction),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Text(
              _importProgress?.fraction == null
                  ? l10n.addProviderSheetLocalImporting
                  : l10n.addProviderSheetLocalImportingProgress(
                      '${((_importProgress!.fraction ?? 0) * 100).round()}%',
                    ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: IosTileButton(
                  icon: Lucide.Upload,
                  label: l10n.localModelManagementImportButton,
                  enabled: !_importing && !_testing,
                  onTap: () => _importNativeModel(cfg),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _testButton(l10n, cfg)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ollamaActions(AppLocalizations l10n, ProviderConfig cfg) {
    return _section(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: IosTileButton(
                  icon: Lucide.Search,
                  label: _discovering
                      ? l10n.localModelManagementDiscovering
                      : l10n.localModelManagementDiscoverButton,
                  enabled: !_discovering && !_testing,
                  onTap: () => _discoverModels(cfg),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _testButton(l10n, cfg)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _testButton(AppLocalizations l10n, ProviderConfig cfg) {
    return IosTileButton(
      icon: Lucide.Activity,
      label: _testing
          ? l10n.localModelManagementTesting
          : l10n.localModelManagementTestButton,
      enabled: !_testing && !_discovering && !_importing,
      onTap: () => _testConnection(cfg),
    );
  }

  Widget _modelsSection(
    AppLocalizations l10n,
    ProviderConfig cfg,
    String? selected,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (cfg.models.isEmpty) {
      return _section(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.localModelManagementNoModelsFound),
          ),
        ],
      );
    }
    return _section(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(
            l10n.localModelManagementDiscoveredModels,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        for (final modelId in cfg.models)
          InkWell(
            onTap: () => setState(() => _selectedModelId = modelId),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(modelId, style: const TextStyle(fontSize: 15)),
                  ),
                  if (modelId == selected)
                    Icon(Lucide.Check, size: 18, color: cs.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _fileRow(AppLocalizations l10n, String path) {
    return FutureBuilder<FileStat?>(
      future: _statFile(path),
      builder: (context, snapshot) {
        final stat = snapshot.data;
        final status = stat == null
            ? l10n.localModelManagementFileMissing
            : l10n.localModelManagementFileSizeBytes(stat.size);
        return Column(
          children: [
            _infoRow(l10n.localModelManagementModelFileLabel, path),
            _infoRow(l10n.localModelManagementFileStatusLabel, status),
          ],
        );
      },
    );
  }

  Future<FileStat?> _statFile(String path) async {
    if (path.trim().isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.stat();
  }

  Widget _section({required List<Widget> children}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? Color.lerp(cs.surface, Colors.white, 0.06)!
        : Color.lerp(cs.surface, Colors.white, 0.92)!;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
          width: 0.6,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _infoRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
