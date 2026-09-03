import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../controllers/music_player_controller.dart';
import '../models/music_models.dart';
import '../providers/music_feature_provider.dart';
import '../services/music_api_client.dart';
import '../theme/music_theme.dart';
import '../widgets/music_album_art.dart';
import '../widgets/music_mini_player.dart';

class MusicPage extends StatelessWidget {
  const MusicPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = _MusicLoader(embedded: embedded);
    return Theme(
      data: buildMusicTheme(Theme.of(context)),
      child: embedded
          ? Material(color: MusicColors.paper, child: content)
          : Scaffold(
              appBar: AppBar(title: Text(l10n.settingsPageMusic)),
              body: content,
            ),
    );
  }
}

class _MusicLoader extends StatefulWidget {
  const _MusicLoader({required this.embedded});

  final bool embedded;

  @override
  State<_MusicLoader> createState() => _MusicLoaderState();
}

class _MusicLoaderState extends State<_MusicLoader> {
  Future<MusicPlayerController>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<MusicFeatureProvider>();
    provider.player?.bindLocalizations(l10n);
    _future ??= provider.initialize(l10n);
  }

  void _retry() {
    setState(() {
      _future = context.read<MusicFeatureProvider>().initialize(
        AppLocalizations.of(context)!,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<MusicFeatureProvider>();
    return FutureBuilder<MusicPlayerController>(
      future: _future,
      builder: (context, snapshot) {
        final player = snapshot.data ?? provider.player;
        if (player != null) {
          return MusicHomeContent(
            api: provider.api,
            player: player,
            embedded: widget.embedded,
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.music_off_outlined,
                      size: 44,
                      color: MusicColors.coral,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.musicInitializationFailed,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: MusicColors.muted),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.musicRetry),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(l10n.musicInitializing),
            ],
          ),
        );
      },
    );
  }
}

class MusicHomeContent extends StatefulWidget {
  const MusicHomeContent({
    super.key,
    required this.api,
    required this.player,
    this.embedded = false,
  });

  final MusicApiClient api;
  final MusicPlayerController player;
  final bool embedded;

  @override
  State<MusicHomeContent> createState() => _MusicHomeContentState();
}

class _MusicHomeContentState extends State<MusicHomeContent> {
  static const _maxSearchHistory = 12;
  static const _historyKey = 'music_search_history_v1';
  static const _sourceKey = 'music_selected_source_v1';

  final _keywordController = TextEditingController();
  final _pageController = TextEditingController(text: '1');
  final _countController = TextEditingController(text: '20');
  MusicSource _selectedSource = musicSources.first;
  BitrateOption _selectedBitrate = bitrateOptions.first;
  List<Track> _tracks = const <Track>[];
  String _status = '';
  bool _loading = false;
  int _currentPage = 1;
  bool _hasSearched = false;
  bool _lastSearchHadResults = false;
  bool _sourceChangedByUser = false;
  bool _localizedStatusSet = false;
  List<String> _searchHistory = const <String>[];
  final Set<String> _selectedTrackIds = <String>{};
  final Map<String, Future<_AlbumArtData?>> _albumArtFutures =
      <String, Future<_AlbumArtData?>>{};

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_syncPlayerStatus);
    unawaited(_loadPreferences());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    widget.player.bindLocalizations(l10n);
    if (!_localizedStatusSet) {
      _localizedStatusSet = true;
      _status = widget.player.status.isEmpty
          ? l10n.musicStatusReady
          : widget.player.status;
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_syncPlayerStatus);
    _keywordController.dispose();
    _pageController.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFEAF4EF),
                      MusicColors.paper,
                      MusicColors.paper,
                    ],
                  ),
                ),
                child: SafeArea(
                  top: !widget.embedded,
                  bottom: false,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      18,
                      18,
                      widget.player.currentTrack == null ? 24 : 112,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final header = _buildHeader();
                            final searchPanel = _buildSearchPanel();
                            final results = _buildResults();
                            if (constraints.maxWidth < 760) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  header,
                                  const SizedBox(height: 16),
                                  searchPanel,
                                  const SizedBox(height: 14),
                                  results,
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                header,
                                const SizedBox(height: 16),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 360, child: searchPanel),
                                    const SizedBox(width: 16),
                                    Expanded(child: results),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: MusicMiniPlayer(player: widget.player),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.musicPageTitle,
              style: const TextStyle(
                color: MusicColors.ink,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.musicPageSubtitle,
              style: const TextStyle(color: MusicColors.muted, fontSize: 14),
            ),
          ],
        ),
        _StatusBadge(text: _status),
      ],
    );
  }

  Widget _buildSearchPanel() {
    final l10n = AppLocalizations.of(context)!;
    final canPage = !_loading && _hasSearched;
    return _MusicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _FeatureIcon(icon: Icons.travel_explore),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.musicSearchTitle,
                      style: const TextStyle(
                        color: MusicColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_selectedSource.label(l10n)} · '
                      '${labelForBitrate(_selectedBitrate.value, l10n)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MusicColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keywordController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchSongs(),
            decoration: InputDecoration(
              hintText: l10n.musicSearchHint,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          _buildSearchHistory(),
          const SizedBox(height: 10),
          DropdownButtonFormField<MusicSource>(
            key: ValueKey(_selectedSource.value),
            initialValue: _selectedSource,
            items: [
              for (final source in musicSources)
                DropdownMenuItem(
                  value: source,
                  child: Text(source.label(l10n)),
                ),
            ],
            onChanged: _loading
                ? null
                : (value) {
                    if (value != null) {
                      _setSelectedSource(value);
                    }
                  },
            decoration: InputDecoration(
              labelText: l10n.musicSource,
              prefixIcon: const Icon(Icons.library_music_outlined),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<BitrateOption>(
            initialValue: _selectedBitrate,
            items: [
              for (final bitrate in bitrateOptions)
                DropdownMenuItem(
                  value: bitrate,
                  child: Text(labelForBitrate(bitrate.value, l10n)),
                ),
            ],
            onChanged: _loading
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _selectedBitrate = value);
                    }
                  },
            decoration: InputDecoration(
              labelText: l10n.musicQuality,
              prefixIcon: const Icon(Icons.graphic_eq),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(labelText: l10n.musicPageNumber),
                  onSubmitted: (_) => _searchSongs(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(labelText: l10n.musicCount),
                  onSubmitted: (_) => _searchSongs(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _loading ? null : _searchSongs,
            icon: Icon(_loading ? Icons.hourglass_top : Icons.search),
            label: Text(_loading ? l10n.musicSearching : l10n.musicSearch),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canPage && _currentPage > 1
                      ? () => _searchAdjacentPage(-1)
                      : null,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.musicPreviousPage),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 78,
                child: Text(
                  l10n.musicPageLabel(_currentPage),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MusicColors.muted,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canPage && _lastSearchHadResults
                      ? () => _searchAdjacentPage(1)
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l10n.musicNextPage),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return _MessagePanel(
        icon: Icons.hourglass_top,
        message: l10n.musicSearchingNow,
      );
    }
    if (!_hasSearched) {
      return _MessagePanel(
        icon: Icons.album_outlined,
        message: l10n.musicSearchPrompt,
      );
    }
    if (_tracks.isEmpty) {
      return _MessagePanel(
        icon: Icons.search_off,
        message: l10n.musicNoResults,
      );
    }
    return Column(
      children: [
        _BatchDownloadBar(
          selectedCount: _selectedTrackIds.length,
          totalCount: _tracks.length,
          downloading: widget.player.downloading,
          onSelectAll: _selectAllResults,
          onClear: _clearSelection,
          onDownload: _selectedTrackIds.isEmpty
              ? null
              : _downloadSelectedTracks,
        ),
        const SizedBox(height: 10),
        for (final track in _tracks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TrackTile(
              key: ValueKey(_trackKey(track)),
              track: track,
              albumArtFuture: _albumArtFutureFor(track),
              playing:
                  widget.player.currentTrack?.id == track.id &&
                  widget.player.currentTrack?.source == track.source,
              selected: _selectedTrackIds.contains(_trackKey(track)),
              onSelectedChanged: (value) => _setTrackSelection(track, value),
              onPlay: () => _playTrack(track),
              onDownload: () => _downloadTrack(track),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.musicDataSource,
            style: const TextStyle(color: MusicColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchHistory() {
    final l10n = AppLocalizations.of(context)!;
    if (_searchHistory.isEmpty) {
      return const SizedBox(height: 10);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: MusicColors.accent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.musicSearchHistory,
                  style: const TextStyle(
                    color: MusicColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _clearSearchHistory,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(l10n.musicClear),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in _searchHistory)
                InputChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      keyword,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onPressed: _loading
                      ? null
                      : () => _searchFromHistory(keyword),
                  onDeleted: _loading
                      ? null
                      : () => _removeSearchHistory(keyword),
                  deleteIcon: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _searchSongs() async {
    final l10n = AppLocalizations.of(context)!;
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      _showSnack(l10n.musicEnterSearchKeyword);
      return;
    }
    final page = _readPositiveInt(_pageController, 1);
    final count = _readPositiveInt(_countController, 20).clamp(1, 50);
    setState(() {
      _loading = true;
      _currentPage = page;
      _pageController.text = page.toString();
      _countController.text = count.toString();
      _status =
          '${l10n.musicSearchingNow}: $keyword '
          '(${l10n.musicPageLabel(page)})';
      _tracks = const <Track>[];
      _selectedTrackIds.clear();
      _albumArtFutures.clear();
    });
    unawaited(_rememberSearch(keyword));
    try {
      final tracks = await widget.api.search(
        source: _selectedSource.value,
        keyword: keyword,
        count: count,
        page: page,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _hasSearched = true;
        _lastSearchHadResults = tracks.isNotEmpty;
        _tracks = tracks;
        _status =
            '${l10n.musicPageLabel(page)} · ${l10n.musicFound}: '
            '${tracks.length} ${l10n.musicTrackUnit}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _hasSearched = true;
        _lastSearchHadResults = false;
        _tracks = const <Track>[];
        _status =
            '${l10n.musicSearchFailed}: '
            '${describeMusicError(error, l10n)}';
      });
    }
  }

  Future<void> _searchAdjacentPage(int offset) async {
    final nextPage = (_readPositiveInt(_pageController, _currentPage) + offset)
        .clamp(1, 999);
    _pageController.text = nextPage.toString();
    await _searchSongs();
  }

  Future<void> _playTrack(Track track) => widget.player.playTrack(
    track,
    _selectedBitrate.value,
    AppLocalizations.of(context)!,
  );

  Future<void> _downloadTrack(Track track) async {
    await widget.player.downloadTrack(
      track,
      _selectedBitrate.value,
      AppLocalizations.of(context)!,
    );
    if (mounted && widget.player.status.isNotEmpty) {
      _showSnack(widget.player.status);
    }
  }

  Future<void> _downloadSelectedTracks() async {
    final selectedTracks = _tracks
        .where((track) => _selectedTrackIds.contains(_trackKey(track)))
        .toList();
    await widget.player.downloadTracks(
      selectedTracks,
      _selectedBitrate.value,
      AppLocalizations.of(context)!,
    );
    if (mounted && widget.player.status.isNotEmpty) {
      _showSnack(widget.player.status);
    }
  }

  void _setTrackSelection(Track track, bool selected) {
    setState(() {
      final key = _trackKey(track);
      selected ? _selectedTrackIds.add(key) : _selectedTrackIds.remove(key);
    });
  }

  void _selectAllResults() {
    setState(() {
      _selectedTrackIds
        ..clear()
        ..addAll(_tracks.map(_trackKey));
    });
  }

  void _clearSelection() => setState(_selectedTrackIds.clear);

  Future<void> _loadPreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final source = _sourceForValue(preferences.getString(_sourceKey));
      final history = _normalizeSearchHistory(
        preferences.getStringList(_historyKey) ?? const <String>[],
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (source != null && !_sourceChangedByUser) {
          _selectedSource = source;
        }
        _searchHistory = history;
      });
    } catch (error, stackTrace) {
      debugPrint('Music preferences load failed: $error\n$stackTrace');
    }
  }

  void _setSelectedSource(MusicSource source) {
    _sourceChangedByUser = true;
    setState(() => _selectedSource = source);
    unawaited(_saveSelectedSource(source));
  }

  Future<void> _saveSelectedSource(MusicSource source) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sourceKey, source.value);
  }

  Future<void> _rememberSearch(String keyword) async {
    final next = _normalizeSearchHistory(<String>[
      keyword.trim(),
      ..._searchHistory,
    ]);
    if (mounted) {
      setState(() => _searchHistory = next);
    }
    await _persistSearchHistory(next);
  }

  Future<void> _removeSearchHistory(String keyword) async {
    final removedKey = keyword.trim().toLowerCase();
    final next = _searchHistory
        .where((item) => item.trim().toLowerCase() != removedKey)
        .toList(growable: false);
    setState(() => _searchHistory = next);
    await _persistSearchHistory(next);
  }

  Future<void> _clearSearchHistory() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _searchHistory = const <String>[]);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_historyKey);
      if (mounted) {
        _showSnack(l10n.musicSearchHistoryCleared);
      }
    } catch (error, stackTrace) {
      debugPrint('Music search history clear failed: $error\n$stackTrace');
      if (mounted) {
        _showSnack(l10n.musicSearchHistoryClearFailed);
      }
    }
  }

  Future<void> _persistSearchHistory(List<String> history) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(_historyKey, history);
    } catch (error, stackTrace) {
      debugPrint('Music search history save failed: $error\n$stackTrace');
    }
  }

  void _searchFromHistory(String keyword) {
    _keywordController.text = keyword;
    _pageController.text = '1';
    unawaited(_searchSongs());
  }

  List<String> _normalizeSearchHistory(List<String> history) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final item in history) {
      final keyword = item.trim();
      final key = keyword.toLowerCase();
      if (keyword.isEmpty || !seen.add(key)) {
        continue;
      }
      normalized.add(keyword);
      if (normalized.length >= _maxSearchHistory) {
        break;
      }
    }
    return List<String>.unmodifiable(normalized);
  }

  Future<_AlbumArtData?>? _albumArtFutureFor(Track track) {
    if (track.picId.isEmpty) {
      return null;
    }
    final key = '${track.source}:${track.picId}';
    return _albumArtFutures.putIfAbsent(key, () async {
      try {
        final url = await widget.api.fetchAlbumUrl(track);
        if (url == null || url.trim().isEmpty) {
          return null;
        }
        try {
          return _AlbumArtData(
            url: url,
            bytes: await widget.api.fetchAlbumBytes(url),
          );
        } catch (error, stackTrace) {
          debugPrint('Music result cover load failed: $error\n$stackTrace');
          return _AlbumArtData(url: url);
        }
      } catch (error, stackTrace) {
        debugPrint('Music result cover URL failed: $error\n$stackTrace');
        return null;
      }
    });
  }

  String _trackKey(Track track) => '${track.source}:${track.id}';

  MusicSource? _sourceForValue(String? value) {
    for (final source in musicSources) {
      if (source.value == value?.trim()) {
        return source;
      }
    }
    return null;
  }

  int _readPositiveInt(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value <= 0 ? fallback : value;
  }

  void _syncPlayerStatus() {
    final value = widget.player.status;
    if (mounted && value.isNotEmpty && value != _status) {
      setState(() => _status = value);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AlbumArtData {
  const _AlbumArtData({required this.url, this.bytes});

  final String url;
  final Uint8List? bytes;
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    super.key,
    required this.track,
    required this.albumArtFuture,
    required this.playing,
    required this.selected,
    required this.onSelectedChanged,
    required this.onPlay,
    required this.onDownload,
  });

  final Track track;
  final Future<_AlbumArtData?>? albumArtFuture;
  final bool playing;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPlay,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: playing ? MusicColors.accentWash : MusicColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: playing ? MusicColors.accent : MusicColors.line,
            width: playing ? 1.4 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: MusicColors.shadow,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Checkbox(
                        value: selected,
                        onChanged: (value) => onSelectedChanged(value ?? false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TrackAlbumArt(
                      albumArtFuture: albumArtFuture,
                      size: compact ? 52 : 58,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  track.name.isEmpty
                                      ? l10n.musicUnknownTrack
                                      : track.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MusicColors.ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (playing)
                                _InfoPill(
                                  icon: Icons.equalizer,
                                  label: l10n.musicPlaying,
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${track.artistText(l10n)} · '
                            '${track.album.isEmpty ? l10n.musicUnknownAlbum : track.album}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MusicColors.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _InfoPill(label: track.sourceLabel(l10n)),
                              if (track.picId.isNotEmpty)
                                _InfoPill(
                                  icon: Icons.image_outlined,
                                  label: l10n.musicCover,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 12),
                      IconButton.filled(
                        tooltip: playing ? l10n.musicReplay : l10n.musicPlay,
                        onPressed: onPlay,
                        icon: Icon(playing ? Icons.replay : Icons.play_arrow),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: l10n.musicDownload,
                        onPressed: onDownload,
                        icon: const Icon(Icons.download),
                      ),
                    ],
                  ],
                ),
                if (compact) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onPlay,
                          icon: Icon(playing ? Icons.replay : Icons.play_arrow),
                          label: Text(
                            playing ? l10n.musicReplay : l10n.musicPlay,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onDownload,
                          icon: const Icon(Icons.download),
                          label: Text(l10n.musicDownload),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrackAlbumArt extends StatelessWidget {
  const _TrackAlbumArt({required this.albumArtFuture, required this.size});

  final Future<_AlbumArtData?>? albumArtFuture;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (albumArtFuture == null) {
      return MusicAlbumArt(url: null, size: size, iconSize: size * 0.48);
    }
    return FutureBuilder<_AlbumArtData?>(
      future: albumArtFuture,
      builder: (context, snapshot) {
        return MusicAlbumArt(
          url: snapshot.data?.url,
          bytes: snapshot.data?.bytes,
          size: size,
          iconSize: size * 0.48,
        );
      },
    );
  }
}

class _BatchDownloadBar extends StatelessWidget {
  const _BatchDownloadBar({
    required this.selectedCount,
    required this.totalCount,
    required this.downloading,
    required this.onSelectAll,
    required this.onClear,
    required this.onDownload,
  });

  final int selectedCount;
  final int totalCount;
  final bool downloading;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _MusicCard(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _InfoPill(
            icon: Icons.library_music_outlined,
            label: selectedCount == 0
                ? '${l10n.musicTotal}: $totalCount ${l10n.musicTrackUnit}'
                : '${l10n.musicSelected}: '
                      '$selectedCount/$totalCount ${l10n.musicTrackUnit}',
          ),
          OutlinedButton.icon(
            onPressed: downloading ? null : onSelectAll,
            icon: const Icon(Icons.select_all),
            label: Text(l10n.musicSelectAll),
          ),
          OutlinedButton.icon(
            onPressed: downloading || selectedCount == 0 ? null : onClear,
            icon: const Icon(Icons.clear),
            label: Text(l10n.musicClear),
          ),
          FilledButton.icon(
            onPressed: downloading ? null : onDownload,
            icon: Icon(downloading ? Icons.hourglass_top : Icons.download),
            label: Text(
              downloading ? l10n.musicDownloading : l10n.musicDownloadSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: MusicColors.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: MusicColors.accentDark),
    );
  }
}

class _MusicCard extends StatelessWidget {
  const _MusicCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MusicColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MusicColors.line),
        boxShadow: const [
          BoxShadow(
            color: MusicColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MusicColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MusicColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: MusicColors.accent, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: MusicColors.accentDark,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: MusicColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MusicColors.line),
          boxShadow: const [
            BoxShadow(
              color: MusicColors.shadow,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq, color: MusicColors.accent, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MusicColors.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _MusicCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(icon, color: MusicColors.accent, size: 34),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MusicColors.muted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
