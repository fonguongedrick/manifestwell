/// Lightweight client-side guard for the anonymous public feed. This is a first
/// line only; server-side moderation (Cloud Function) must back it once the
/// feed is shared across real users.
class Moderation {
  static const maxLength = 220;

  static const _blocked = <String>[
    'fuck', 'shit', 'bitch', 'cunt', 'asshole', 'dick', 'nigg', 'fag',
    'kill myself', 'kill yourself', 'suicide', 'rape', 'nazi',
  ];

  static final _link = RegExp(r'(https?:\/\/|www\.|\.com\b|\.net\b|@\w+)', caseSensitive: false);
  static final _phone = RegExp(r'\d{3}[\s.-]?\d{3}[\s.-]?\d{4}');

  /// Returns a gentle message if the text can't go in the public Well,
  /// or null when it's fine. [extraBlocked] is the admin's own list, matched as
  /// whole words or phrases (the same rule the server uses to auto-hide).
  static String? check(String raw, {List<String> extraBlocked = const []}) {
    final text = raw.trim();
    if (text.isEmpty) return 'Write a wish first.';
    if (text.length > maxLength) return 'Keep it under $maxLength characters.';
    final lower = text.toLowerCase();
    for (final w in _blocked) {
      if (lower.contains(w)) {
        return 'Let\'s keep the Well positive. Try rewording your wish.';
      }
    }
    for (final term in extraBlocked) {
      if (term.trim().length < 2) continue;
      final word = RegExp(
        '(^|[^\\p{L}\\p{N}])${RegExp.escape(term.trim())}(\$|[^\\p{L}\\p{N}])',
        caseSensitive: false,
        unicode: true,
      );
      if (word.hasMatch(text)) {
        return 'Let\'s keep the Well positive. Try rewording your wish.';
      }
    }
    if (_link.hasMatch(text) || _phone.hasMatch(text)) {
      return 'Links and contact details can\'t go in the Well.';
    }
    return null;
  }
}
