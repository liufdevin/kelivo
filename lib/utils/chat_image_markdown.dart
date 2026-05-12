import 'dart:io';

class ChatImageMarkdown {
  ChatImageMarkdown._();

  static final RegExp _markdownImageRe = RegExp(
    r'!\[[^\]]*\]\(([^)]+)\)',
    multiLine: true,
  );
  static final RegExp _windowsPathRe = RegExp(r'^[a-zA-Z]:[\\/]');

  static List<String> extractEditableImagePaths(String markdown) {
    final paths = <String>[];
    final seen = <String>{};
    for (final match in _markdownImageRe.allMatches(markdown)) {
      final path = _editableLocalImagePath(match.group(1) ?? '');
      if (path == null || seen.contains(path)) continue;
      paths.add(path);
      seen.add(path);
    }
    return List.unmodifiable(paths);
  }

  static String? _editableLocalImagePath(String rawTarget) {
    var target = rawTarget.trim();
    if (target.isEmpty) return null;
    if (target.startsWith('<')) {
      final close = target.indexOf('>');
      if (close > 0) {
        target = target.substring(1, close).trim();
      }
    }

    if (target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('data:')) {
      return null;
    }

    final String path;
    if (target.startsWith('file://')) {
      try {
        path = Uri.parse(target).toFilePath(windows: Platform.isWindows);
      } catch (_) {
        return null;
      }
    } else if (target.startsWith('/') || _windowsPathRe.hasMatch(target)) {
      path = target;
    } else {
      return null;
    }

    return _hasEditableImageExtension(path) ? path : null;
  }

  static bool _hasEditableImageExtension(String path) {
    final normalized = path.split('?').first.split('#').first.toLowerCase();
    return normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp');
  }
}
