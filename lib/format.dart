/// Money and date formatting helpers (no external packages needed).
library;

String formatMoney(int cents, String currency) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final frac = (abs % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '${negative ? '-' : ''}$currency$buf.$frac';
}

/// Parses user input like "12", "12.5", "1,234.56" into cents.
/// Returns null for invalid or negative input.
int? parseMoney(String input) {
  final cleaned = input.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(cleaned) || cleaned == '.') {
    return null;
  }
  final parts = cleaned.split('.');
  final whole = parts[0].isEmpty ? 0 : int.parse(parts[0]);
  final frac = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return whole * 100 + int.parse(frac);
}

/// Formats cents for pre-filling a text field (no currency, no separators).
String centsToInput(int cents) {
  if (cents % 100 == 0) return (cents ~/ 100).toString();
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String formatShortDate(DateTime d) => '${_months[d.month - 1]}\n${d.day}';
