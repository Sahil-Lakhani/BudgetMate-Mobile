import 'package:intl/intl.dart';

String _pad(int n) => n.toString().padLeft(2, '0');

/// Local calendar month "YYYY-MM" (web: localMonth).
String localMonth([DateTime? d]) {
  final x = d ?? DateTime.now();
  return '${x.year}-${_pad(x.month)}';
}

/// Local calendar date "YYYY-MM-DD" (web: localDate).
String localDate([DateTime? d]) {
  final x = d ?? DateTime.now();
  return '${localMonth(x)}-${_pad(x.day)}';
}

/// Parses a JS-style number (string or num); null if not finite.
double? parseNum(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) {
    final m = RegExp(r'^\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?').firstMatch(v);
    if (m == null) return null;
    final p = double.tryParse(m.group(0)!.trim());
    return (p != null && p.isFinite) ? p : null;
  }
  return null;
}

/// Unit price of a scanned receipt item. Gemini's `price` is the line total, so prefer
/// `unit_price` and otherwise divide the total by the quantity (rounded to cents).
String scannedUnitPrice(Map item) {
  final unit = parseNum(item['unit_price']);
  if (unit != null) return _numText(unit);
  final total = parseNum(item['price']) ?? 0;
  final qty = parseNum(item['quantity']);
  if (qty == null || qty <= 0) return _numText(total);
  return _numText((total / qty * 100).round() / 100);
}

String _numText(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

/// "YYYY-MM" → DateTime on the 1st of that month (local).
DateTime monthDate(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], 1);
}

/// "YYYY-MM" → "October 2026" (or "October" when [withYear] is false).
String monthLabel(String key, {bool withYear = true}) =>
    DateFormat(withYear ? 'MMMM y' : 'MMMM', 'en_US').format(monthDate(key));

/// Upper-cases the first letter (web: name.charAt(0).toUpperCase() + name.slice(1)).
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
