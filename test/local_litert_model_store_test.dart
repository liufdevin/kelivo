import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/local_litert_model_store.dart';

void main() {
  group('LocalLiteRtModelStore helpers', () {
    test('infers a model id from a litertlm file name', () {
      expect(
        inferLiteRtModelIdFromFileName('gemma-4-E4B-it.litertlm'),
        'gemma-4-E4B-it',
      );
      expect(
        inferGgufModelIdFromFileName('qwen2.5-3b-instruct.gguf'),
        'qwen2.5-3b-instruct',
      );
    });

    test('sanitizes imported file names and preserves extension', () {
      expect(safeLiteRtModelFileName('../gemma:4?E4B'), 'gemma_4_E4B.litertlm');
      expect(safeGgufModelFileName('../qwen:3b?'), 'qwen_3b_.gguf');
      expect(
        safeLiteRtModelFileName('gemma-4-E4B-it.litertlm'),
        'gemma-4-E4B-it.litertlm',
      );
      expect(
        safeGgufModelFileName('qwen2.5-3b-instruct.gguf'),
        'qwen2.5-3b-instruct.gguf',
      );
    });

    test('uses stable fallbacks for blank names', () {
      expect(
        inferLiteRtModelIdFromFileName('.litertlm'),
        'imported-local-model',
      );
      expect(safeLiteRtModelFileName('???'), '___.litertlm');
      expect(safeGgufModelFileName('???'), '___.gguf');
    });

    test('copies streams and reports progress', () async {
      final temp = await Directory.systemTemp.createTemp('kelivo_litert_');
      addTearDown(() => temp.delete(recursive: true));
      final target = File(
        '${temp.path}${Platform.pathSeparator}model.litertlm',
      );
      final progress = <LocalLiteRtImportProgress>[];

      await importLiteRtModelStream(
        sourceStream: Stream<List<int>>.fromIterable([
          [1, 2],
          [3, 4, 5],
        ]),
        target: target,
        totalBytes: 5,
        onProgress: progress.add,
      );

      expect(await target.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(progress.map((p) => p.bytesCopied), [2, 5, 5]);
      expect(progress.last.fraction, 1.0);
    });
  });
}
