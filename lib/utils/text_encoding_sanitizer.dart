import 'dart:convert';

String repairMojibakeText(String raw) {
  if (raw.isEmpty || !_hasMojibakeSignal(raw)) return raw;

  var current = raw;
  for (var i = 0; i < 3; i++) {
    final repaired = _decodeUtf8FromWindows1252(current);
    if (repaired == null || repaired == current) break;
    if (!_isBetterRepair(current, repaired)) break;
    current = repaired;
    if (!_hasMojibakeSignal(current)) break;
  }
  return current;
}

bool _hasMojibakeSignal(String text) {
  return RegExp(
    r'[ÃÂÐÑØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïð�\u0080-\u009F]',
  ).hasMatch(text);
}

String? _decodeUtf8FromWindows1252(String text) {
  final bytes = <int>[];
  for (final rune in text.runes) {
    final byte = _windows1252ByteForRune(rune);
    if (byte == null) return null;
    bytes.add(byte);
  }

  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return null;
  }
}

int? _windows1252ByteForRune(int rune) {
  if (rune <= 0xFF) return rune;
  return switch (rune) {
    0x20AC => 0x80,
    0x201A => 0x82,
    0x0192 => 0x83,
    0x201E => 0x84,
    0x2026 => 0x85,
    0x2020 => 0x86,
    0x2021 => 0x87,
    0x02C6 => 0x88,
    0x2030 => 0x89,
    0x0160 => 0x8A,
    0x2039 => 0x8B,
    0x0152 => 0x8C,
    0x017D => 0x8E,
    0x2018 => 0x91,
    0x2019 => 0x92,
    0x201C => 0x93,
    0x201D => 0x94,
    0x2022 => 0x95,
    0x2013 => 0x96,
    0x2014 => 0x97,
    0x02DC => 0x98,
    0x2122 => 0x99,
    0x0161 => 0x9A,
    0x203A => 0x9B,
    0x0153 => 0x9C,
    0x017E => 0x9E,
    0x0178 => 0x9F,
    _ => null,
  };
}

bool _isBetterRepair(String original, String repaired) {
  final originalScore = _textQualityScore(original);
  final repairedScore = _textQualityScore(repaired);
  return repairedScore > originalScore + 2;
}

int _textQualityScore(String text) {
  var score = 0;
  for (final rune in text.runes) {
    if (_isCjk(rune)) {
      score += 4;
    } else if (_isAsciiText(rune)) {
      score += 1;
    } else if (rune == 0xFFFD) {
      score -= 8;
    } else if ((rune >= 0x80 && rune <= 0x9F) || _isMojibakeLead(rune)) {
      score -= 4;
    }
  }
  return score;
}

bool _isCjk(int rune) {
  return (rune >= 0x3400 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF);
}

bool _isAsciiText(int rune) {
  return (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      rune == 0x20;
}

bool _isMojibakeLead(int rune) {
  return switch (rune) {
    0x00C2 ||
    0x00C3 ||
    0x00C4 ||
    0x00C5 ||
    0x00C6 ||
    0x00C7 ||
    0x00C8 ||
    0x00C9 ||
    0x00CE ||
    0x00E2 ||
    0x00E3 ||
    0x00E4 ||
    0x00E5 ||
    0x00E6 ||
    0x00E7 ||
    0x00E8 ||
    0x00E9 => true,
    _ => false,
  };
}
