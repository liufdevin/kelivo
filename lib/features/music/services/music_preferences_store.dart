import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MusicPreferencesStore {
  MusicPreferencesStore._();

  static final MusicPreferencesStore instance = MusicPreferencesStore._();

  Future<void> _pendingWrite = Future<void>.value();

  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    return File(p.join(root.path, 'music', 'preferences.json'));
  }

  Future<Map<String, dynamic>> _read() async {
    final file = await _file();
    if (!await file.exists()) return <String, dynamic>{};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }

  Future<String?> selectedSource() async {
    final value = (await _read())['selectedSource'];
    return value is String ? value : null;
  }

  Future<List<String>> searchHistory() async {
    final value = (await _read())['searchHistory'];
    return value is List
        ? value.whereType<String>().toList(growable: false)
        : const <String>[];
  }

  Future<void> setSelectedSource(String value) {
    return _update((data) => data['selectedSource'] = value);
  }

  Future<void> setSearchHistory(List<String> value) {
    return _update((data) => data['searchHistory'] = value);
  }

  Future<void> clearSearchHistory() {
    return _update((data) => data.remove('searchHistory'));
  }

  Future<void> _update(void Function(Map<String, dynamic> data) change) {
    final next = _pendingWrite.then((_) async {
      final data = await _read();
      change(data);
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(data), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
    _pendingWrite = next.catchError((_) {});
    return next;
  }
}
