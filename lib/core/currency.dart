import 'package:intl/intl.dart';

class Currency {
  const Currency(this.code, this.symbol, this.label);
  final String code;
  final String symbol;
  final String label;
}

/// Same list as the web app's src/lib/currency.js
const currencies = <Currency>[
  Currency('EUR', '€', 'Euro (EUR)'),
  Currency('USD', r'$', 'US Dollar (USD)'),
  Currency('GBP', '£', 'British Pound (GBP)'),
  Currency('INR', '₹', 'Indian Rupee (INR)'),
  Currency('JPY', '¥', 'Japanese Yen (JPY)'),
  Currency('CAD', r'CA$', 'Canadian Dollar (CAD)'),
  Currency('AUD', r'A$', 'Australian Dollar (AUD)'),
];

String currencySymbol(String code) {
  for (final c in currencies) {
    if (c.code == code) return c.symbol;
  }
  return '€';
}

final _formatters = <String, NumberFormat>{};

/// Matches `Intl.NumberFormat('en', { style: 'currency' })`: -€12.00, ¥1,200, CA$5.00.
String formatCurrency(Object? amount, [String code = 'EUR']) {
  final c = currencies.any((x) => x.code == code) ? code : 'EUR';
  final f = _formatters.putIfAbsent(
    c,
    () => NumberFormat.currency(locale: 'en', name: c, symbol: currencySymbol(c), decimalDigits: c == 'JPY' ? 0 : 2),
  );
  final double value;
  if (amount is num) {
    value = amount.toDouble();
  } else {
    value = double.tryParse('${amount ?? ''}'.trim()) ?? 0;
  }
  return f.format(value.isFinite ? value : 0);
}
