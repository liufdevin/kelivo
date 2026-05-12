import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/openai_image_service.dart';
import '../../../features/chat/pages/image_viewer_page.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';

class ImageGenerationPage extends StatefulWidget {
  const ImageGenerationPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ImageGenerationPage> createState() => _ImageGenerationPageState();
}

class _ImageGenerationPageState extends State<ImageGenerationPage> {
  static const List<String> _sizes = <String>[
    '1024x1024',
    '1024x1536',
    '1536x1024',
  ];
  static const List<String> _qualities = <String>[
    'auto',
    'low',
    'medium',
    'high',
  ];
  static const List<String> _formats = <String>['png', 'jpeg', 'webp'];

  final TextEditingController _modelCtrl = TextEditingController(
    text: 'gpt-image-2',
  );
  final TextEditingController _promptCtrl = TextEditingController();
  final TextEditingController _countCtrl = TextEditingController(text: '1');

  String? _providerKey;
  bool _editMode = false;
  String _size = _sizes.first;
  String _quality = _qualities.first;
  String _format = _formats.first;
  bool _submitting = false;
  List<String> _inputImages = const <String>[];
  String? _maskImage;
  List<String> _resultImages = const <String>[];

  @override
  void dispose() {
    _modelCtrl.dispose();
    _promptCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  List<MapEntry<String, ProviderConfig>> _openAIProviders(
    SettingsProvider settings,
  ) {
    final configs = settings.providerConfigs;
    final seen = <String>{};
    final ordered = <MapEntry<String, ProviderConfig>>[];
    for (final key in settings.providersOrder) {
      final config = configs[key];
      if (config == null) continue;
      if (ProviderConfig.classify(key, explicitType: config.providerType) !=
          ProviderKind.openai) {
        continue;
      }
      if (!config.enabled) continue;
      ordered.add(MapEntry(key, config));
      seen.add(key);
    }
    for (final entry in configs.entries) {
      if (seen.contains(entry.key)) continue;
      final config = entry.value;
      if (ProviderConfig.classify(
            entry.key,
            explicitType: config.providerType,
          ) !=
          ProviderKind.openai) {
        continue;
      }
      if (!config.enabled) continue;
      ordered.add(entry);
    }
    return ordered;
  }

  void _ensureProviderSelected(List<MapEntry<String, ProviderConfig>> items) {
    if (items.isEmpty) {
      if (_providerKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _providerKey = null);
        });
      }
      return;
    }
    if (_providerKey != null && items.any((e) => e.key == _providerKey)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _providerKey = items.first.key);
    });
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['png', 'jpg', 'jpeg', 'webp'],
      allowMultiple: true,
    );
    if (!mounted || result == null) return;
    final paths = result.paths
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) return;
    setState(() => _inputImages = paths);
  }

  Future<void> _pickMaskImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['png'],
      allowMultiple: false,
    );
    if (!mounted || result == null) return;
    final path = result.files.single.path?.trim();
    if (path == null || path.isEmpty) return;
    setState(() => _maskImage = path);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final key = _providerKey;
    if (key == null || key.isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.imageGenerationNoProvider,
        type: NotificationType.error,
      );
      return;
    }
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.imageGenerationPromptRequired,
        type: NotificationType.error,
      );
      return;
    }
    if (_editMode && _inputImages.isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.imageGenerationImageRequired,
        type: NotificationType.error,
      );
      return;
    }
    final count = int.tryParse(_countCtrl.text.trim())?.clamp(1, 4) ?? 1;
    final config = settings.getProviderConfig(key);
    setState(() {
      _submitting = true;
      _resultImages = const <String>[];
    });
    try {
      final result = _editMode
          ? await OpenAIImageService.edit(
              config: config,
              prompt: prompt,
              imagePaths: _inputImages,
              maskPath: _maskImage,
              model: _modelCtrl.text,
              size: _size,
              quality: _quality,
              outputFormat: _format,
              n: count,
            )
          : await OpenAIImageService.generate(
              config: config,
              prompt: prompt,
              model: _modelCtrl.text,
              size: _size,
              quality: _quality,
              outputFormat: _format,
              n: count,
            );
      if (!mounted) return;
      setState(() => _resultImages = result.imagePaths);
      showAppSnackBar(
        context,
        message: l10n.imageGenerationSuccess(result.imagePaths.length),
        type: NotificationType.success,
      );
    } on OpenAIImageServiceException catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: _localizedServiceError(l10n, e.message),
        type: NotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.imageGenerationFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _localizedServiceError(AppLocalizations l10n, String message) {
    switch (message) {
      case 'missing_api_key':
        return l10n.imageGenerationNoApiKey;
      case 'missing_prompt':
        return l10n.imageGenerationPromptRequired;
      case 'missing_edit_image':
        return l10n.imageGenerationImageRequired;
      case 'empty_image_response':
        return l10n.imageGenerationEmptyResult;
      case 'invalid_response':
        return l10n.imageGenerationInvalidResponse;
      case 'request_failed':
        return l10n.imageGenerationRequestFailed;
      default:
        return l10n.imageGenerationFailed(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final providers = _openAIProviders(settings);
    _ensureProviderSelected(providers);

    final body = _buildBody(context, l10n, providers);
    if (widget.embedded) {
      return Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: Theme.of(context).colorScheme.onSurface,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.imageGenerationPageTitle),
      ),
      body: body,
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    List<MapEntry<String, ProviderConfig>> providers,
  ) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, widget.embedded ? 12 : 16, 16, 24),
            children: [
              if (widget.embedded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.imageGenerationPageTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              _section(
                context,
                children: [
                  _dropdownRow(
                    context: context,
                    label: l10n.imageGenerationProviderLabel,
                    value: _providerKey,
                    hint: l10n.imageGenerationNoProvider,
                    items: [
                      for (final entry in providers)
                        DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            entry.value.name.isEmpty
                                ? entry.key
                                : entry.value.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: providers.isEmpty
                        ? null
                        : (value) => setState(() => _providerKey = value),
                  ),
                  _divider(context),
                  IosFormTextField(
                    label: l10n.imageGenerationModelLabel,
                    controller: _modelCtrl,
                    outerPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    cursorToEndOnTap: true,
                  ),
                  _divider(context),
                  _dropdownRow(
                    context: context,
                    label: l10n.imageGenerationModeLabel,
                    value: _editMode ? 'edit' : 'generate',
                    items: [
                      DropdownMenuItem<String>(
                        value: 'generate',
                        child: Text(l10n.imageGenerationModeGenerate),
                      ),
                      DropdownMenuItem<String>(
                        value: 'edit',
                        child: Text(l10n.imageGenerationModeEdit),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _editMode = value == 'edit'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _section(
                context,
                children: [
                  IosFormTextField(
                    label: l10n.imageGenerationPromptLabel,
                    hintText: l10n.imageGenerationPromptHint,
                    controller: _promptCtrl,
                    minLines: 4,
                    maxLines: 8,
                    inlineLabel: false,
                    textCapitalization: TextCapitalization.sentences,
                    outerPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  if (_editMode) ...[
                    _divider(context),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.imageGenerationPickedImages(
                                    _inputImages.length,
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                              _smallButton(
                                context,
                                icon: Lucide.Image,
                                label: l10n.imageGenerationPickImages,
                                onTap: _pickImages,
                              ),
                              if (_inputImages.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _smallButton(
                                  context,
                                  icon: Lucide.X,
                                  label: l10n.imageGenerationClearImages,
                                  onTap: () => setState(
                                    () => _inputImages = const <String>[],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_inputImages.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _imageStrip(_inputImages),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _maskImage == null
                                      ? l10n.imageGenerationMaskNotSelected
                                      : l10n.imageGenerationMaskSelected,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                              _smallButton(
                                context,
                                icon: Lucide.Image,
                                label: l10n.imageGenerationPickMask,
                                onTap: _pickMaskImage,
                              ),
                              if (_maskImage != null) ...[
                                const SizedBox(width: 8),
                                _smallButton(
                                  context,
                                  icon: Lucide.X,
                                  label: l10n.imageGenerationClearMask,
                                  onTap: () =>
                                      setState(() => _maskImage = null),
                                ),
                              ],
                            ],
                          ),
                          if (_maskImage != null) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: 76,
                              height: 76,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _imageFromPath(_maskImage!),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _section(
                context,
                children: [
                  _dropdownRow(
                    context: context,
                    label: l10n.imageGenerationSizeLabel,
                    value: _size,
                    items: [
                      for (final value in _sizes)
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                    ],
                    onChanged: (value) => setState(() => _size = value!),
                  ),
                  _divider(context),
                  _dropdownRow(
                    context: context,
                    label: l10n.imageGenerationQualityLabel,
                    value: _quality,
                    items: [
                      for (final value in _qualities)
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                    ],
                    onChanged: (value) => setState(() => _quality = value!),
                  ),
                  _divider(context),
                  _dropdownRow(
                    context: context,
                    label: l10n.imageGenerationOutputFormatLabel,
                    value: _format,
                    items: [
                      for (final value in _formats)
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                    ],
                    onChanged: (value) => setState(() => _format = value!),
                  ),
                  _divider(context),
                  IosFormTextField(
                    label: l10n.imageGenerationCountLabel,
                    controller: _countCtrl,
                    keyboardType: TextInputType.number,
                    fieldWidth: 76,
                    outerPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    selectAllOnFocus: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _submitButton(context, l10n),
              if (_resultImages.isNotEmpty) ...[
                const SizedBox(height: 16),
                _resultSection(context, l10n),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, {required List<Widget> children}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96),
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

  Widget _divider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 6,
      thickness: 0.6,
      indent: 12,
      endIndent: 12,
      color: cs.outlineVariant.withValues(alpha: 0.18),
    );
  }

  Widget _dropdownRow({
    required BuildContext context,
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 8,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white12
                    : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  hint: hint == null
                      ? null
                      : Text(hint, overflow: TextOverflow.ellipsis),
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(12),
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      baseColor: cs.primary.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final label = _submitting
        ? l10n.imageGenerationGenerating
        : _editMode
        ? l10n.imageGenerationEditButton
        : l10n.imageGenerationGenerateButton;
    return IosCardPress(
      onTap: _submitting ? null : _submit,
      borderRadius: BorderRadius.circular(12),
      baseColor: cs.primary,
      pressedScale: 0.99,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_submitting)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.onPrimary,
              ),
            )
          else
            Icon(Lucide.Image, size: 18, color: cs.onPrimary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultSection(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return _section(
      context,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.imageGenerationResultTitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _resultImages.length,
                itemBuilder: (context, index) {
                  final path = _resultImages[index];
                  return IosCardPress(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ImageViewerPage(
                            images: _resultImages,
                            initialIndex: index,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _imageFromPath(path),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _imageStrip(List<String> paths) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 76,
              height: 76,
              child: _imageFromPath(paths[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _imageFromPath(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }
}
