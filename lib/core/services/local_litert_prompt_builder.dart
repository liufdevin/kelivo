class LocalLiteRtPrompt {
  const LocalLiteRtPrompt({
    required this.systemPrompt,
    required this.prompt,
    required this.omittedTurnCount,
  });

  final String systemPrompt;
  final String prompt;
  final int omittedTurnCount;
}

const int localLiteRtMaxPromptChars = 8000;
const int localLiteRtKeepRecentTurns = 6;

LocalLiteRtPrompt buildLocalLiteRtPrompt(
  List<Map<String, dynamic>> messages, {
  int maxPromptChars = localLiteRtMaxPromptChars,
  int keepRecentTurns = localLiteRtKeepRecentTurns,
}) {
  assert(maxPromptChars > 0);
  assert(keepRecentTurns > 0);

  final system = <String>[];
  final turns = <String>[];
  for (final message in messages) {
    final role = (message['role'] ?? 'user').toString().trim().toLowerCase();
    final content = localLiteRtMessageContentAsText(message['content']).trim();
    if (content.isEmpty) continue;
    switch (role) {
      case 'system':
        system.add(content);
      case 'assistant':
        turns.add('Assistant: $content');
      case 'tool':
        turns.add('Tool: $content');
      case 'user':
      default:
        turns.add('User: $content');
    }
  }

  final fullPrompt = turns.join('\n\n');
  if (fullPrompt.length <= maxPromptChars) {
    return LocalLiteRtPrompt(
      systemPrompt: _localLiteRtSystemPrompt(system, omittedTurnCount: 0),
      prompt: fullPrompt,
      omittedTurnCount: 0,
    );
  }

  final kept = <String>[];
  var usedChars = 0;
  final recentTurnFloor = turns.length - keepRecentTurns;
  for (var i = turns.length - 1; i >= 0 && i >= recentTurnFloor; i--) {
    final separatorChars = kept.isEmpty ? 0 : 2;
    final available = maxPromptChars - usedChars - separatorChars;
    if (available <= 0) break;

    final turn = turns[i];
    if (turn.length <= available) {
      kept.insert(0, turn);
      usedChars += turn.length + separatorChars;
    } else if (kept.isEmpty) {
      kept.insert(0, turn.substring(turn.length - available));
      usedChars = maxPromptChars;
    } else {
      break;
    }
  }

  final omittedTurnCount = turns.length - kept.length;
  return LocalLiteRtPrompt(
    systemPrompt: _localLiteRtSystemPrompt(
      system,
      omittedTurnCount: omittedTurnCount,
    ),
    prompt: kept.join('\n\n'),
    omittedTurnCount: omittedTurnCount,
  );
}

String localLiteRtMessageContentAsText(dynamic content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map) {
        final text = item['text'];
        if (text is String && text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }
  return content.toString();
}

String _localLiteRtSystemPrompt(
  List<String> system, {
  required int omittedTurnCount,
}) {
  final base = system.isEmpty
      ? 'You are a helpful assistant.'
      : system.join('\n\n');
  if (omittedTurnCount <= 0) return base;
  return '$base\n\nEarlier conversation turns were omitted to keep local inference stable.';
}
