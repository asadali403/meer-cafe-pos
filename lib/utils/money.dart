/// Money helpers. All amounts in the app are integer **paisa** (1 Rupee = 100 paisa)
/// so no floating-point arithmetic is ever used for prices or totals.
class Money {
  Money._();

  static const int paisaPerRupee = 100;

  /// Formats paisa as `Rs. 1,250.00`.
  static String format(int paisa, {bool symbol = true}) {
    final negative = paisa < 0;
    final abs = paisa.abs();
    final rupees = abs ~/ paisaPerRupee;
    final cents = abs % paisaPerRupee;
    final text = '${_group(rupees)}.${cents.toString().padLeft(2, '0')}';
    final signed = negative ? '-$text' : text;
    return symbol ? 'Rs. $signed' : signed;
  }

  /// Plain decimal form without grouping, e.g. `1250.00` (for CSV / input fields).
  static String plain(int paisa) {
    final negative = paisa < 0;
    final abs = paisa.abs();
    final s = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
    return negative ? '-$s' : s;
  }

  /// Input-field form: drops `.00` so `25000` paisa becomes `250`.
  static String input(int paisa) {
    if (paisa % 100 == 0) return (paisa ~/ 100).toString();
    return plain(paisa);
  }

  /// Parses user input such as `250`, `250.5`, `1,250.75`, `Rs. 99` into paisa.
  /// Returns null for empty, negative, malformed input or more than 2 decimals.
  static int? parse(String input) {
    var s = input.trim().replaceAll(',', '');
    if (s.toLowerCase().startsWith('rs.')) s = s.substring(3).trim();
    if (s.toLowerCase().startsWith('rs')) s = s.substring(2).trim();
    if (s.isEmpty) return null;
    final match = RegExp(r'^(\d{1,9})(?:\.(\d{0,2}))?$').firstMatch(s);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final frac = (match.group(2) ?? '').padRight(2, '0');
    return whole * paisaPerRupee + int.parse(frac.isEmpty ? '0' : frac);
  }

  static String _group(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
