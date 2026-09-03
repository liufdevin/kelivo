import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class SavedDownload {
  const SavedDownload(this.displayPath);

  final String displayPath;
}

Future<String?> pickBatchDownloadDirectory({
  required String confirmButtonText,
}) {
  return getDirectoryPath(
    confirmButtonText: confirmButtonText,
    canCreateDirectories: true,
  );
}

Future<SavedDownload?> saveDownloadBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String audioTypeLabel,
  required String confirmButtonText,
  required String androidSaveError,
  String? targetPath,
}) async {
  final savePath =
      targetPath ??
      (await getSaveLocation(
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: audioTypeLabel,
            extensions: const <String>[
              'mp3',
              'flac',
              'm4a',
              'aac',
              'ogg',
              'wav',
            ],
            mimeTypes: const <String>[
              'audio/mpeg',
              'audio/flac',
              'audio/mp4',
              'audio/aac',
              'audio/ogg',
              'audio/wav',
            ],
            webWildCards: const <String>['audio/*'],
          ),
        ],
        suggestedName: fileName,
        confirmButtonText: confirmButtonText,
      ))?.path;
  if (savePath == null) {
    return null;
  }
  await XFile.fromData(
    bytes,
    name: fileName,
    mimeType: mimeType,
  ).saveTo(savePath);
  return SavedDownload(savePath);
}
