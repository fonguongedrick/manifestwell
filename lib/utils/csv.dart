/// Minimal CSV writer for admin exports.
class Csv {
  Csv._();

  /// Rows to RFC 4180 text (CRLF line ends, quotes doubled). Wishes are
  /// strangers' words, and a spreadsheet runs any cell that starts with = + - @
  /// as a formula, so those get a leading apostrophe and stay plain text.
  static String encode(List<List<Object?>> rows) =>
      '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';

  static String _cell(Object? v) {
    var s = switch (v) {
      null => '',
      DateTime d => d.toUtc().toIso8601String(),
      _ => '$v',
    };
    if (v is String && s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
    if (s.contains(RegExp(r'[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
    return s;
  }
}
