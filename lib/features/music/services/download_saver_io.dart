import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class SavedDownload {
  const SavedDownload(this.displayPath);

  final String displayPath;
}

const _androidDownloadFolder = 'kelivo_music';

Future<String?> pickBatchDownloadDirectory({
  required String confirmButtonText,
}) {
  if (Platform.isAndroid) {
    return Future<String?>.value(_androidDownloadFolder);
  }
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
  if (Platform.isAndroid) {
    return _saveAndroidDownload(
      bytes: bytes,
      fileName: fileName,
      errorMessage: androidSaveError,
    );
  }
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

Future<SavedDownload> _saveAndroidDownload({
  required Uint8List bytes,
  required String fileName,
  required String errorMessage,
}) async {
  await _ensureMediaStore();
  final tempDirectory = await getTemporaryDirectory();
  final tempFile = File(path.join(tempDirectory.path, fileName));
  await tempFile.writeAsBytes(bytes, flush: true);
  try {
    final saveInfo = await MediaStore().saveFile(
      tempFilePath: tempFile.path,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: _androidDownloadFolder,
    );
    if (saveInfo == null) {
      throw Exception(errorMessage);
    }
    return SavedDownload('Download/$_androidDownloadFolder/$fileName');
  } finally {
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}

Future<void>? _mediaStoreInit;

Future<void> _ensureMediaStore() {
  MediaStore.appFolder = _androidDownloadFolder;
  return _mediaStoreInit ??= MediaStore.ensureInitialized();
}
