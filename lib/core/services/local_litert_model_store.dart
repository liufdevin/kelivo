import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

enum LocalLiteRtImportError {
  notLiteRtModel,
  notGgufModel,
  emptyFile,
  unreadableSource,
}

class LocalLiteRtImportException implements Exception {
  const LocalLiteRtImportException(this.error);

  final LocalLiteRtImportError error;
}

class ImportedLocalLiteRtModel {
  const ImportedLocalLiteRtModel({
    required this.fileName,
    required this.modelId,
    required this.path,
  });

  final String fileName;
  final String modelId;
  final String path;
}

class LocalLiteRtImportProgress {
  const LocalLiteRtImportProgress({
    required this.bytesCopied,
    required this.totalBytes,
  });

  final int bytesCopied;
  final int totalBytes;

  double? get fraction {
    if (totalBytes <= 0) return null;
    return (bytesCopied / totalBytes).clamp(0.0, 1.0);
  }
}

class LocalLiteRtModelStore {
  static Future<ImportedLocalLiteRtModel?> pickAndImportModel({
    void Function(LocalLiteRtImportProgress progress)? onProgress,
  }) async {
    return _pickAndImportModel(
      extension: 'litertlm',
      fallbackFileName: 'imported-model.litertlm',
      invalidExtensionError: LocalLiteRtImportError.notLiteRtModel,
      inferModelId: inferLiteRtModelIdFromFileName,
      onProgress: onProgress,
    );
  }

  static Future<ImportedLocalLiteRtModel?> pickAndImportGgufModel({
    void Function(LocalLiteRtImportProgress progress)? onProgress,
  }) async {
    return _pickAndImportModel(
      extension: 'gguf',
      fallbackFileName: 'imported-model.gguf',
      invalidExtensionError: LocalLiteRtImportError.notGgufModel,
      inferModelId: inferGgufModelIdFromFileName,
      onProgress: onProgress,
    );
  }

  static Future<ImportedLocalLiteRtModel?> _pickAndImportModel({
    required String extension,
    required String fallbackFileName,
    required LocalLiteRtImportError invalidExtensionError,
    required String Function(String fileName) inferModelId,
    void Function(LocalLiteRtImportProgress progress)? onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [extension],
      allowMultiple: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final fileName = safeLocalModelFileName(
      picked.name,
      extension: extension,
      fallbackFileName: fallbackFileName,
    );
    if (!fileName.toLowerCase().endsWith('.$extension')) {
      throw LocalLiteRtImportException(invalidExtensionError);
    }

    final dir = await _modelDir();
    final target = File(_joinPath(dir.path, fileName));
    final temp = File('${target.path}.importing');
    if (await temp.exists()) await temp.delete();

    final sourceStream =
        picked.readStream ??
        (picked.path == null ? null : File(picked.path!).openRead());
    if (sourceStream == null) {
      throw const LocalLiteRtImportException(
        LocalLiteRtImportError.unreadableSource,
      );
    }

    await importLiteRtModelStream(
      sourceStream: sourceStream,
      target: temp,
      totalBytes: picked.size,
      onProgress: onProgress,
    );

    if (!await temp.exists() || await temp.length() <= 0) {
      if (await temp.exists()) await temp.delete();
      throw const LocalLiteRtImportException(LocalLiteRtImportError.emptyFile);
    }

    if (await target.exists()) await target.delete();
    await temp.rename(target.path);

    return ImportedLocalLiteRtModel(
      fileName: fileName,
      modelId: inferModelId(fileName),
      path: target.path,
    );
  }

  static Future<Directory> _modelDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(_joinPath(root.path, 'local_models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

Future<void> importLiteRtModelStream({
  required Stream<List<int>> sourceStream,
  required File target,
  required int totalBytes,
  void Function(LocalLiteRtImportProgress progress)? onProgress,
}) async {
  var copied = 0;
  final sink = target.openWrite();
  try {
    await for (final chunk in sourceStream) {
      sink.add(chunk);
      copied += chunk.length;
      onProgress?.call(
        LocalLiteRtImportProgress(bytesCopied: copied, totalBytes: totalBytes),
      );
    }
  } catch (_) {
    await sink.close();
    if (await target.exists()) await target.delete();
    rethrow;
  }
  await sink.close();
  onProgress?.call(
    LocalLiteRtImportProgress(bytesCopied: copied, totalBytes: totalBytes),
  );
}

String inferLiteRtModelIdFromFileName(String fileName) {
  return inferLocalModelIdFromFileName(fileName, extension: 'litertlm');
}

String inferGgufModelIdFromFileName(String fileName) {
  return inferLocalModelIdFromFileName(fileName, extension: 'gguf');
}

String inferLocalModelIdFromFileName(
  String fileName, {
  required String extension,
}) {
  final base = fileName
      .split('/')
      .last
      .split('\\')
      .last
      .replaceFirst(RegExp('\\.$extension\$', caseSensitive: false), '');
  final normalized = base.trim();
  return normalized.isEmpty ? 'imported-local-model' : normalized;
}

String safeLiteRtModelFileName(String name) {
  return safeLocalModelFileName(
    name,
    extension: 'litertlm',
    fallbackFileName: 'imported-model.litertlm',
  );
}

String safeGgufModelFileName(String name) {
  return safeLocalModelFileName(
    name,
    extension: 'gguf',
    fallbackFileName: 'imported-model.gguf',
  );
}

String safeLocalModelFileName(
  String name, {
  required String extension,
  required String fallbackFileName,
}) {
  final base = name.split('/').last.split('\\').last;
  final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
  final fallback = cleaned.isEmpty ? fallbackFileName : cleaned;
  return fallback.toLowerCase().endsWith('.$extension')
      ? fallback
      : '$fallback.$extension';
}

String _joinPath(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) return '$parent$child';
  return '$parent${Platform.pathSeparator}$child';
}
