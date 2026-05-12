import '../providers/settings_provider.dart';

const String defaultLocalProviderBaseUrl = 'http://192.168.1.6:8080/v1';
const String defaultLocalProviderApiKey = 'ollama';
const String defaultLocalProviderModelId = 'llama3.2';
const String localLiteRtRuntime = 'litertlm';
const String localGgufRuntime = 'gguf';
const String defaultLocalLiteRtModelId = 'gemma-4-E4B-it';
const String defaultLocalGgufModelId = 'imported-gguf-model';
const Set<String> localProviderHosts = {
  '127.0.0.1',
  'localhost',
  '0.0.0.0',
  '::1',
};

ProviderConfig buildLocalOpenAICompatibleProviderConfig({
  required String id,
  required String name,
  required bool enabled,
  required String apiKey,
  required String baseUrl,
  required String modelId,
}) {
  final normalizedModelId = modelId.trim().isEmpty
      ? defaultLocalProviderModelId
      : modelId.trim();
  final normalizedBaseUrl = baseUrl.trim().isEmpty
      ? defaultLocalProviderBaseUrl
      : baseUrl.trim();

  return ProviderConfig(
    id: id,
    enabled: enabled,
    name: name,
    apiKey: apiKey.trim(),
    baseUrl: normalizedBaseUrl,
    providerType: ProviderKind.openai,
    chatPath: '/chat/completions',
    useResponseApi: false,
    models: [normalizedModelId],
    modelOverrides: {
      normalizedModelId: {
        'name': normalizedModelId,
        'type': 'chat',
        'input': ['text'],
        'output': ['text'],
      },
    },
    proxyEnabled: false,
    proxyHost: '',
    proxyPort: '8080',
    proxyUsername: '',
    proxyPassword: '',
    aihubmixAppCodeEnabled: false,
  );
}

ProviderConfig buildLocalLiteRtProviderConfig({
  required String id,
  required String name,
  required bool enabled,
  required String modelPath,
  required String modelId,
}) {
  final normalizedModelPath = modelPath.trim();
  final normalizedModelId = modelId.trim().isEmpty
      ? defaultLocalLiteRtModelId
      : modelId.trim();

  return ProviderConfig(
    id: id,
    enabled: enabled,
    name: name,
    apiKey: '',
    baseUrl: normalizedModelPath,
    providerType: ProviderKind.openai,
    chatPath: null,
    useResponseApi: false,
    models: [normalizedModelId],
    modelOverrides: {
      normalizedModelId: {
        'name': normalizedModelId,
        'type': 'chat',
        'input': ['text'],
        'output': ['text'],
        'localRuntime': localLiteRtRuntime,
        'localModelPath': normalizedModelPath,
      },
    },
    proxyEnabled: false,
    proxyHost: '',
    proxyPort: '8080',
    proxyUsername: '',
    proxyPassword: '',
    aihubmixAppCodeEnabled: false,
  );
}

ProviderConfig buildLocalGgufProviderConfig({
  required String id,
  required String name,
  required bool enabled,
  required String modelPath,
  required String modelId,
}) {
  final normalizedModelPath = modelPath.trim();
  final normalizedModelId = modelId.trim().isEmpty
      ? defaultLocalGgufModelId
      : modelId.trim();

  return ProviderConfig(
    id: id,
    enabled: enabled,
    name: name,
    apiKey: '',
    baseUrl: normalizedModelPath,
    providerType: ProviderKind.openai,
    chatPath: null,
    useResponseApi: false,
    models: [normalizedModelId],
    modelOverrides: {
      normalizedModelId: {
        'name': normalizedModelId,
        'type': 'chat',
        'input': ['text'],
        'output': ['text'],
        'localRuntime': localGgufRuntime,
        'localModelPath': normalizedModelPath,
      },
    },
    proxyEnabled: false,
    proxyHost: '',
    proxyPort: '8080',
    proxyUsername: '',
    proxyPassword: '',
    aihubmixAppCodeEnabled: false,
  );
}

bool isLocalLiteRtProvider(ProviderConfig cfg) {
  if (cfg.baseUrl.trim().toLowerCase().endsWith('.litertlm')) {
    return true;
  }
  for (final value in cfg.modelOverrides.values) {
    if (value is! Map) continue;
    final runtime = value['localRuntime']?.toString().trim().toLowerCase();
    final path = value['localModelPath']?.toString().trim().toLowerCase();
    if (runtime == localLiteRtRuntime ||
        (path?.endsWith('.litertlm') ?? false)) {
      return true;
    }
  }
  return false;
}

bool isLocalGgufProvider(ProviderConfig cfg) {
  if (cfg.baseUrl.trim().toLowerCase().endsWith('.gguf')) {
    return true;
  }
  for (final value in cfg.modelOverrides.values) {
    if (value is! Map) continue;
    final runtime = value['localRuntime']?.toString().trim().toLowerCase();
    final path = value['localModelPath']?.toString().trim().toLowerCase();
    if (runtime == localGgufRuntime || (path?.endsWith('.gguf') ?? false)) {
      return true;
    }
  }
  return false;
}

bool isLocalNativeModelProvider(ProviderConfig cfg) {
  return isLocalLiteRtProvider(cfg) || isLocalGgufProvider(cfg);
}

bool isLocalOpenAICompatibleProvider(ProviderConfig cfg) {
  if (isLocalNativeModelProvider(cfg)) return false;
  final baseUrl = cfg.baseUrl.trim();
  if (baseUrl.isEmpty) return false;
  final uri = Uri.tryParse(baseUrl);
  final host = uri?.host.toLowerCase();
  if (host != null && localProviderHosts.contains(host)) return true;
  return cfg.id.toLowerCase().contains('local') ||
      cfg.name.toLowerCase().contains('local');
}

bool isLocalProviderConfig(ProviderConfig cfg) {
  return isLocalNativeModelProvider(cfg) ||
      isLocalOpenAICompatibleProvider(cfg);
}

String localLiteRtModelPath(ProviderConfig cfg, String modelId) {
  return localRuntimeModelPath(cfg, modelId);
}

String localGgufModelPath(ProviderConfig cfg, String modelId) {
  return localRuntimeModelPath(cfg, modelId);
}

String localRuntimeModelPath(ProviderConfig cfg, String modelId) {
  final override = cfg.modelOverrides[modelId];
  if (override is Map) {
    final path = override['localModelPath']?.toString().trim();
    if (path != null && path.isNotEmpty) return path;
  }
  return cfg.baseUrl.trim();
}
