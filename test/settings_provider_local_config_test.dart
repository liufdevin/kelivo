import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'support/business_test_harness.dart';

Future<void> _waitForSettingsLoad() async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

BusinessTestHarness? _latestHarness;

Future<SettingsProvider> _createSettings() async {
  final localPreferences = await SharedPreferences.getInstance();
  final initial = <String, Object>{};
  for (final key in localPreferences.getKeys()) {
    final value = localPreferences.get(key);
    if (value != null) initial[key] = value;
  }
  final harness = await createBusinessTestHarness(
    initial: initial,
    localInitial: initial,
  );
  _latestHarness = harness;
  final settings = SettingsProvider(harness.preferences);
  await settings.loaded;
  return settings;
}

Future<SettingsProvider> _reloadSettings() async {
  final harness = _latestHarness;
  if (harness == null) throw StateError('No settings harness to reload');
  final settings = SettingsProvider(harness.preferences);
  await settings.loaded;
  return settings;
}

Future<void> _withCurrentDirectory(
  Directory directory,
  Future<void> Function() body,
) async {
  final previous = Directory.current;
  Directory.current = directory;
  try {
    await body();
  } finally {
    Directory.current = previous;
  }
}

Map<String, Object?> _providerJson(String key, {String? name}) => {
  'enabled': true,
  'name': name ?? key,
  'apiKey': '',
  'baseUrl': 'https://${key.toLowerCase()}.example/v1',
  'providerType': 'openai',
  'chatPath': '/chat/completions',
  'useResponseApi': false,
  'models': ['$key-chat'],
  'modelOverrides': {
    '$key-chat': {
      'type': 'chat',
      'input': ['text'],
      'output': ['text'],
    },
  },
};

Future<void> _writeLocalProviderConfig(File file, String key) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      'providersOrder': [key],
      'providers': {key: _providerJson(key)},
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider local provider config', () {
    test('defaults to local_config provider json before root json', () async {
      final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
      addTearDown(() => temp.delete(recursive: true));

      await _writeLocalProviderConfig(
        File('${temp.path}/provider_configs.local.json'),
        'RootAI',
      );
      await _writeLocalProviderConfig(
        File('${temp.path}/local_config/provider_configs.local.json'),
        'LocalConfigAI',
      );

      await _withCurrentDirectory(temp, () async {
        SharedPreferences.setMockInitialValues({});
        final settings = await _createSettings();

        await _waitForSettingsLoad();

        expect(settings.providerConfigs, contains('LocalConfigAI'));
        expect(settings.providerConfigs, isNot(contains('RootAI')));
        expect(settings.providersOrder.first, 'LocalConfigAI');
      });
    });

    test('uses provider config selected by source file', () async {
      final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
      addTearDown(() => temp.delete(recursive: true));

      await _writeLocalProviderConfig(
        File('${temp.path}/local_config/provider_configs.local.json'),
        'DefaultAI',
      );
      await _writeLocalProviderConfig(
        File('${temp.path}/configs/selected_provider_configs.json'),
        'SelectedAI',
      );
      await File(
        '${temp.path}/local_config/provider_config_source.json',
      ).writeAsString(
        jsonEncode({'path': 'configs/selected_provider_configs.json'}),
      );

      await _withCurrentDirectory(temp, () async {
        SharedPreferences.setMockInitialValues({});
        final settings = await _createSettings();

        await _waitForSettingsLoad();

        expect(settings.providerConfigs, contains('SelectedAI'));
        expect(settings.providerConfigs, isNot(contains('DefaultAI')));
        expect(settings.providersOrder.first, 'SelectedAI');
      });
    });

    test(
      'replace merge mode overwrites provider metadata but preserves models',
      () async {
        final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
        addTearDown(() => temp.delete(recursive: true));

        await _writeLocalProviderConfig(
          File('${temp.path}/configs/selected_provider_configs.json'),
          'SameAI',
        );
        await Directory('${temp.path}/local_config').create(recursive: true);
        await File(
          '${temp.path}/local_config/provider_config_source.json',
        ).writeAsString(
          jsonEncode({
            'path': 'configs/selected_provider_configs.json',
            'mergeMode': 'replace',
          }),
        );

        await _withCurrentDirectory(temp, () async {
          SharedPreferences.setMockInitialValues({
            'provider_configs_v1': jsonEncode({
              'SameAI': {
                'id': 'SameAI',
                'enabled': true,
                'name': 'Persisted Same AI',
                'apiKey': '',
                'baseUrl': 'https://persisted.example/v1',
                'providerType': 'openai',
                'models': ['persisted-chat'],
                'modelOverrides': <String, Object?>{},
              },
              'OldAI': {
                'id': 'OldAI',
                'enabled': true,
                'name': 'Old AI',
                'apiKey': '',
                'baseUrl': 'https://old.example/v1',
                'providerType': 'openai',
                'models': ['old-chat'],
                'modelOverrides': <String, Object?>{},
              },
            }),
            'selected_model_v1': 'OldAI::old-chat',
          });
          final settings = await _createSettings();

          await _waitForSettingsLoad();

          final cfg = settings.getProviderConfig('SameAI');
          expect(cfg.name, 'SameAI');
          expect(cfg.baseUrl, 'https://sameai.example/v1');
          expect(cfg.models, ['SameAI-chat', 'persisted-chat']);
          expect(settings.providerConfigs, isNot(contains('OldAI')));
          expect(settings.currentModelProvider, isNull);
          expect(settings.currentModelId, isNull);
        });
      },
    );

    test(
      'replace merge mode does not clear persisted user-added models when local list is empty',
      () async {
        final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
        addTearDown(() => temp.delete(recursive: true));

        await File('${temp.path}/provider_configs.local.json').writeAsString(
          jsonEncode({
            'providersOrder': ['SameAI'],
            'providers': {
              'SameAI': {
                'enabled': true,
                'name': 'Local Same AI',
                'apiKey': '',
                'baseUrl': 'https://local.example/v1',
                'providerType': 'openai',
                'models': <String>[],
                'cachedModels': <String>[],
                'modelOverrides': <String, Object?>{},
              },
            },
          }),
        );
        await Directory('${temp.path}/local_config').create(recursive: true);
        await File(
          '${temp.path}/local_config/provider_config_source.json',
        ).writeAsString(
          jsonEncode({
            'path': 'provider_configs.local.json',
            'mergeMode': 'replace',
          }),
        );

        await _withCurrentDirectory(temp, () async {
          SharedPreferences.setMockInitialValues({
            'provider_configs_v1': jsonEncode({
              'SameAI': {
                'id': 'SameAI',
                'enabled': true,
                'name': 'Persisted Same AI',
                'apiKey': '',
                'baseUrl': 'https://persisted.example/v1',
                'providerType': 'openai',
                'models': ['manual-chat'],
                'cachedModels': ['manual-chat', 'fetched-chat'],
                'modelOverrides': {
                  'manual-chat': {
                    'type': 'chat',
                    'input': ['text'],
                    'output': ['text'],
                  },
                },
              },
            }),
          });
          final settings = await _createSettings();

          await _waitForSettingsLoad();

          final cfg = settings.getProviderConfig('SameAI');
          expect(cfg.name, 'Local Same AI');
          expect(cfg.baseUrl, 'https://local.example/v1');
          expect(cfg.models, ['manual-chat']);
          expect(cfg.cachedModels, ['manual-chat', 'fetched-chat']);
          expect(cfg.modelOverrides, contains('manual-chat'));
        });
      },
    );

    test('loads providers and preferred order from local json', () async {
      final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
      addTearDown(() => temp.delete(recursive: true));

      await File('${temp.path}/provider_configs.local.json').writeAsString(
        jsonEncode({
          'providersOrder': ['LocalAI'],
          'providers': {
            'LocalAI': {
              'enabled': true,
              'name': 'Local AI',
              'apiKey': 'local-key',
              'baseUrl': 'https://local.example/v1',
              'providerType': 'openai',
              'chatPath': '/chat/completions',
              'useResponseApi': false,
              'models': ['local-chat'],
              'modelOverrides': {
                'local-chat': {
                  'type': 'chat',
                  'input': ['text'],
                  'output': ['text'],
                },
              },
            },
          },
        }),
      );
      await Directory('${temp.path}/local_config').create(recursive: true);
      await File(
        '${temp.path}/local_config/provider_config_source.json',
      ).writeAsString(jsonEncode({'path': 'provider_configs.local.json'}));

      await _withCurrentDirectory(temp, () async {
        SharedPreferences.setMockInitialValues({});
        final settings = await _createSettings();

        await _waitForSettingsLoad();

        final cfg = settings.getProviderConfig('LocalAI');
        expect(settings.providerConfigs, contains('LocalAI'));
        expect(settings.providersOrder.first, 'LocalAI');
        expect(cfg.name, 'Local AI');
        expect(cfg.apiKey, 'local-key');
        expect(cfg.baseUrl, 'https://local.example/v1');
        expect(cfg.models, ['local-chat']);
      });
    });

    test('keeps persisted providers when local json is missing', () async {
      final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
      addTearDown(() => temp.delete(recursive: true));
      await Directory('${temp.path}/local_config').create(recursive: true);
      await File(
        '${temp.path}/local_config/provider_config_source.json',
      ).writeAsString('');

      await _withCurrentDirectory(temp, () async {
        SharedPreferences.setMockInitialValues({
          'provider_configs_v1': jsonEncode({
            'PersistedAI': {
              'id': 'PersistedAI',
              'enabled': true,
              'name': 'Persisted AI',
              'apiKey': '',
              'baseUrl': 'https://persisted.example/v1',
              'providerType': 'openai',
              'models': <String>[],
              'modelOverrides': <String, Object?>{},
            },
          }),
        });
        final settings = await _createSettings();

        await _waitForSettingsLoad();

        expect(settings.providerConfigs, contains('PersistedAI'));
        expect(settings.providerConfigs, isNot(contains('LocalAI')));
      });
    });

    test(
      'persists fetched provider model cache across provider reloads',
      () async {
        final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
        addTearDown(() => temp.delete(recursive: true));
        await Directory('${temp.path}/local_config').create(recursive: true);
        await File(
          '${temp.path}/local_config/provider_config_source.json',
        ).writeAsString('');

        await _withCurrentDirectory(temp, () async {
          SharedPreferences.setMockInitialValues({});
          final settings = await _createSettings();

          await _waitForSettingsLoad();

          await settings.setProviderConfig(
            'CachedAI',
            ProviderConfig.defaultsFor('CachedAI').copyWith(
              models: const ['model-a'],
              cachedModels: const ['model-a', 'model-b'],
            ),
          );

          final reloaded = await _reloadSettings();
          await _waitForSettingsLoad();

          final cfg = reloaded.getProviderConfig('CachedAI');
          expect(cfg.models, ['model-a']);
          expect(cfg.cachedModels, ['model-a', 'model-b']);
        });
      },
    );

    test('local json does not overwrite persisted user-added models', () async {
      final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
      addTearDown(() => temp.delete(recursive: true));

      await File('${temp.path}/provider_configs.local.json').writeAsString(
        jsonEncode({
          'providersOrder': ['SameAI'],
          'providers': {
            'SameAI': {
              'enabled': true,
              'name': 'Local Same AI',
              'apiKey': '',
              'baseUrl': 'https://local.example/v1',
              'providerType': 'openai',
              'models': <String>[],
              'cachedModels': <String>[],
              'modelOverrides': <String, Object?>{},
            },
          },
        }),
      );
      await Directory('${temp.path}/local_config').create(recursive: true);
      await File(
        '${temp.path}/local_config/provider_config_source.json',
      ).writeAsString(jsonEncode({'path': 'provider_configs.local.json'}));

      await _withCurrentDirectory(temp, () async {
        SharedPreferences.setMockInitialValues({
          'provider_configs_v1': jsonEncode({
            'SameAI': {
              'id': 'SameAI',
              'enabled': true,
              'name': 'Persisted Same AI',
              'apiKey': '',
              'baseUrl': 'https://persisted.example/v1',
              'providerType': 'openai',
              'models': ['manual-chat'],
              'cachedModels': ['manual-chat', 'fetched-chat'],
              'modelOverrides': <String, Object?>{},
            },
          }),
        });
        final settings = await _createSettings();

        await _waitForSettingsLoad();

        final cfg = settings.getProviderConfig('SameAI');
        expect(cfg.name, 'Persisted Same AI');
        expect(cfg.baseUrl, 'https://persisted.example/v1');
        expect(cfg.models, ['manual-chat']);
        expect(cfg.cachedModels, ['manual-chat', 'fetched-chat']);
        expect(settings.providersOrder.first, 'SameAI');
      });
    });

    test('invalid local json does not hide persisted providers', () async {
      final temp = await Directory.systemTemp.createTemp('kelivo_provider_');
      addTearDown(() => temp.delete(recursive: true));

      await File(
        '${temp.path}/provider_configs.local.json',
      ).writeAsString('{bad json');
      await Directory('${temp.path}/local_config').create(recursive: true);
      await File(
        '${temp.path}/local_config/provider_config_source.json',
      ).writeAsString(jsonEncode({'path': 'provider_configs.local.json'}));

      await _withCurrentDirectory(temp, () async {
        SharedPreferences.setMockInitialValues({
          'provider_configs_v1': jsonEncode({
            'PersistedAI': {
              'id': 'PersistedAI',
              'enabled': true,
              'name': 'Persisted AI',
              'apiKey': '',
              'baseUrl': 'https://persisted.example/v1',
              'providerType': 'openai',
              'models': <String>[],
              'modelOverrides': <String, Object?>{},
            },
          }),
        });
        final settings = await _createSettings();

        await _waitForSettingsLoad();

        expect(settings.providerConfigs, contains('PersistedAI'));
        expect(settings.providerConfigs, isNot(contains('LocalAI')));
      });
    });
  });
}
