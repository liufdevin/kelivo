import '../../../utils/text_encoding_sanitizer.dart';

String sanitizeTitleGenerationMessageContent(String raw) {
  if (raw.trim().isEmpty) return '';
  return raw
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\[image:[^\]]+\]'), ' ')
      .replaceAll(RegExp(r'\[file:[^\]]+\]'), ' ')
      .replaceAll(
        RegExp(r'data:image\/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=\r\n]+'),
        ' ',
      )
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String sanitizeGeneratedConversationTitle(String raw) {
  final cleaned = repairMojibakeText(raw)
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'["“”‘’`*_#]'), '')
      .replaceAll(RegExp(r'^[\s"“”‘’`*_#-]+|[\s"“”‘’`*_#-]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.length <= 60) return cleaned;
  return cleaned.substring(0, 60).trim();
}
