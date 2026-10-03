// Unit tests for the logic ported from the web app (validation.js, balances.js,
// currency.js, rateLimit.js, Dashboard/Expenses/Analytics/Insights calculations).
import 'package:budgetmate/core/balances.dart';
import 'package:budgetmate/core/currency.dart';
import 'package:budgetmate/core/errors.dart';
import 'package:budgetmate/core/rate_limit.dart';
import 'package:budgetmate/core/utils.dart';
import 'package:budgetmate/core/validation.dart';
import 'package:budgetmate/data/models.dart';
import 'package:budgetmate/screens/analytics_screen.dart';
import 'package:budgetmate/screens/dashboard_screen.dart';
import 'package:budgetmate/screens/expenses_screen.dart';
import 'package:budgetmate/screens/split_screen.dart';
import 'package:budgetmate/widgets/insights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Txn tx(String id, String date, num total, {String merchant = 'Shop', List<Map<String, dynamic>>? items, String type = 'expense', String source = 'manual'}) =>
    Txn.fromMap(id, {
      'merchant': merchant,
      'date': date,
      'total': total,
      'lineItems': items ?? [
        {'name': 'Milk', 'category': 'Groceries', 'quantity': 1, 'price': total, 'totalPrice': total}
      ],
      'type': type,
      'source': source,
    });

GroupSplit split(String id, String payer, List<(String, num, String)> parts, {String groupId = 'g1'}) => GroupSplit.fromMap(id, {
      'groupId': groupId,
      'payerId': payer,
      'merchant': 'Dinner',
      'date': '2026-10-01',
      'totalAmount': parts.fold<num>(0, (s, p) => s + p.$2),
      'participants': [
        for (final p in parts) {'userId': p.$1, 'displayName': p.$1.toUpperCase(), 'amount': p.$2, 'status': p.$3}
      ],
    });

void main() {
  group('validateTransaction (TransactionSchema)', () {
    test('normalizes a manual transaction like Zod', () {
      final out = validateTransaction({
        'merchant': 'REWE',
        'date': '2026-10-02',
        'location': '',
        'total': 3.5,
        'source': 'manual',
        'lineItems': [
          {'name': 'Milk', 'category': 'Groceries', 'quantity': '2', 'price': '1.75', 'totalPrice': 3.5, 'extra': 'dropped'}
        ],
        'unknown': 'stripped',
      });
      expect(out, {
        'merchant': 'REWE',
        'location': '',
        'total': 3.5,
        'date': '2026-10-02',
        'lineItems': [
          {'name': 'Milk', 'category': 'Groceries', 'quantity': 2, 'price': 1.75, 'totalPrice': 3.5}
        ],
        'source': 'manual',
        'type': 'expense',
      });
    });

    test('defaults source to scan and category to Other', () {
      final out = validateTransaction({
        'merchant': 'X',
        'date': '2026-01-01',
        'total': 1,
        'lineItems': [
          {'name': 'a', 'price': 1}
        ],
      });
      expect(out['source'], 'scan');
      expect((out['lineItems'] as List).first['category'], 'Other');
      expect((out['lineItems'] as List).first['quantity'], 1);
    });

    test('rejects bad input', () {
      expect(() => validateTransaction({'merchant': '', 'date': '2026-01-01', 'total': 1, 'lineItems': []}), throwsA(isA<ValidationError>()));
      expect(() => validateTransaction({'merchant': 'a', 'date': '01/01/2026', 'total': 1, 'lineItems': [{'name': 'x', 'price': 1}]}),
          throwsA(isA<ValidationError>()));
      // expense needs line items and a non-negative total
      expect(() => validateTransaction({'merchant': 'a', 'date': '2026-01-01', 'total': 1, 'lineItems': []}), throwsA(isA<ValidationError>()));
      expect(() => validateTransaction({'merchant': 'a', 'date': '2026-01-01', 'total': -1, 'lineItems': [{'name': 'x', 'price': 1}]}),
          throwsA(isA<ValidationError>()));
    });

    test('refunds must be negative and may have no items', () {
      final out = validateTransaction({'merchant': 'a', 'date': '2026-01-01', 'total': -5, 'lineItems': [], 'type': 'refund', 'source': 'split'});
      expect(out['total'], -5);
      expect(() => validateTransaction({'merchant': 'a', 'date': '2026-01-01', 'total': 5, 'type': 'refund'}), throwsA(isA<ValidationError>()));
    });
  });

  group('validateSplit / validateGroup / settings', () {
    test('shares must add up and payer must participate', () {
      final ok = validateSplit({
        'groupId': 'g',
        'payerId': 'a',
        'merchant': ' Pizza ',
        'date': '2026-10-01',
        'totalAmount': 30,
        'participants': [
          {'userId': 'a', 'amount': 10},
          {'userId': 'b', 'amount': 20},
        ],
      });
      expect(ok['merchant'], 'Pizza');
      expect((ok['participants'] as List).first['status'], 'pending');

      expect(
          () => validateSplit({
                'groupId': 'g',
                'payerId': 'a',
                'merchant': 'x',
                'date': '2026-10-01',
                'totalAmount': 30,
                'participants': [
                  {'userId': 'a', 'amount': 10}
                ],
              }),
          throwsA(isA<ValidationError>()));
      expect(
          () => validateSplit({
                'groupId': 'g',
                'payerId': 'z',
                'merchant': 'x',
                'date': '2026-10-01',
                'totalAmount': 10,
                'participants': [
                  {'userId': 'a', 'amount': 10}
                ],
              }),
          throwsA(isA<ValidationError>()));
    });

    test('group members must be unique and within the limit', () {
      final m = {'userId': 'a'};
      expect(() => validateGroup({'name': 'Trip', 'members': [m, m]}), throwsA(isA<ValidationError>()));
      expect(() => validateGroup({'name': ' ', 'members': [m]}), throwsA(isA<ValidationError>()));
      expect(validateGroup({'name': ' Trip ', 'members': [m]})['name'], 'Trip');
      expect(() => validateGroup({'name': 'x', 'members': List.generate(21, (i) => {'userId': '$i'})}), throwsA(isA<ValidationError>()));
    });

    test('settings keep unknown keys (passthrough) and fill defaults', () {
      final s = validateUserSettings({'income': '3000', 'aiInsights': true});
      expect(s, {'income': '3000', 'aiInsights': true, 'currency': 'EUR', 'language': 'en', 'notifications': true});
    });

    test('notifications match the rules allow-list shape', () {
      expect(validateNotification({'type': 'group_added', 'groupId': 'g'}), {'type': 'group_added', 'groupId': 'g', 'groupName': '', 'addedByName': ''});
      expect(() => validateNotification({'type': 'other'}), throwsA(isA<ValidationError>()));
    });
  });

  group('balances (balances.js)', () {
    test('payer is owed unsettled shares; settled shares count for nothing', () {
      final b = computeBalances([
        split('s1', 'me', [('me', 10, 'settled'), ('bob', 10, 'pending'), ('amy', 10, 'settled')]),
        split('s2', 'bob', [('bob', 5, 'settled'), ('me', 7.5, 'pending')]),
      ], 'me');
      expect(b.owedToYou, 10);
      expect(b.youOwe, 7.5);
      expect(b.net, 2.5);
      expect(b.byMember.keys, ['bob']);
      expect(b.byMember['bob']!.amount, 2.5);
      expect(b.byMember['bob']!.displayName, 'BOB');
    });

    test('distributeEvenly gives the rounding remainder to the payer', () {
      expect(distributeEvenly(10, 3, 1), [3.33, 3.34, 3.33]);
      expect(distributeEvenly(10, 3, -1), [3.34, 3.33, 3.33]);
      expect(distributeEvenly(10, 0), isEmpty);
    });

    test('normaliseTotal rejects untrusted amounts', () {
      expect(normaliseTotal('12.345'), 12.35);
      expect(normaliseTotal(-1), isNull);
      expect(normaliseTotal('abc'), isNull);
      expect(normaliseTotal(null), isNull);
    });
  });

  group('currency (currency.js / Intl en)', () {
    test('formats like Intl.NumberFormat("en", {style: "currency"})', () {
      expect(formatCurrency(12, 'EUR'), '€12.00');
      expect(formatCurrency(-12, 'EUR'), '-€12.00');
      expect(formatCurrency(1234.5, 'USD'), r'$1,234.50');
      expect(formatCurrency(1200, 'JPY'), '¥1,200');
      expect(formatCurrency('5', 'CAD'), r'CA$5.00');
      expect(formatCurrency(5, 'XYZ'), '€5.00');
      expect(formatCurrency('junk', 'GBP'), '£0.00');
    });
    test('symbols', () {
      expect(currencySymbol('INR'), '₹');
      expect(currencySymbol('nope'), '€');
    });
  });

  group('rate limiter (rateLimit.js)', () {
    test('allows max calls per window then throws a user-facing error', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 10, 3, 12);
      final limiter = RateLimiter(prefs, now: () => now);
      for (var i = 0; i < 3; i++) {
        limiter.check('gemini-insights');
      }
      expect(() => limiter.check('gemini-insights'), throwsA(isA<UserFacingError>()));
      now = now.add(const Duration(seconds: 61));
      limiter.check('gemini-insights'); // window passed
      limiter.check('unknown-action'); // no limit configured
    });
  });

  group('screen calculations', () {
    final now = DateTime(2026, 10, 15);
    final data = [
      tx('1', '2026-10-02', 40, merchant: 'REWE'),
      tx('2', '2026-10-05', 10, merchant: 'Lidl', items: [
        {'name': 'Shirt', 'category': 'Clothing', 'price': 10}
      ]),
      tx('3', '2026-09-20', 25, merchant: 'REWE'),
      tx('4', '2026-10-06', -5, type: 'refund', source: 'split', items: []),
      tx('5', '2025-12-31', 100),
    ];

    test('dashboard stats (calculateStats)', () {
      final s = computeDashboardStats(data, const UserSettings({'income': '3000', 'savingsType': 'percentage', 'savingsValue': '20'}), now: now);
      expect(s.monthlyTotal, 45); // 40 + 10 - 5 refund
      expect(s.yearlyTotal, 70);
      expect(s.savingsAmount, 600);
      expect(s.spendableAmount, 2400);
      expect(s.remainingSpendable, 2355);
      expect(s.categoryTotals, {'Groceries': 165, 'Clothing': 10}); // refunds excluded
      expect(computeDashboardStats(data, null, now: now).income, 0);
    });

    test('expenses filter (month, search, category)', () {
      expect(filterTransactions(data, month: '2026-10', search: '', category: 'All').map((t) => t.id), ['1', '2', '4']);
      expect(filterTransactions(data, month: '2026-10', search: 'shirt', category: 'All').map((t) => t.id), ['2']);
      expect(filterTransactions(data, month: '2026-10', search: '', category: 'Groceries').map((t) => t.id), ['1']);
      expect(filterTransactions(data, month: '2026-10', search: 'rewe', category: 'All').map((t) => t.id), ['1']);
    });

    test('analytics: last six months and top categories', () {
      final m = monthlyTotals(data, now: now);
      expect(m.map((e) => e.name), ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct']);
      expect(m.last.total, 45);
      expect(m[4].total, 25);
      final cats = topCategories(data);
      expect(cats.first.name, 'Groceries');
      expect(cats.first.count, 3);
    });

    test('rule-based insights: price comparison and trend', () {
      final tips = ruleBasedInsights([
        tx('a', '2026-10-01', 2, merchant: 'Aldi', items: [{'name': 'Coffee', 'price': 2, 'quantity': 1}]),
        tx('b', '2026-10-03', 4, merchant: 'Edeka', items: [{'name': 'coffee', 'price': 4, 'quantity': 1}]),
        tx('c', '2026-09-10', 1, merchant: 'Aldi', items: [{'name': 'Tea', 'price': 1}]),
      ], 'EUR', now: now);
      expect(tips.map((t) => t.title), ['Spending Alert', 'Smart Shopper Tip']);
      expect(tips[1].message, 'You paid €4.00 for coffee at Edeka, but it was only €2.00 at Aldi.');
      expect(tips[0].message, "You've spent €5.00 (500.0%) more this month compared to last month.");
    });
  });

  group('utils', () {
    test('local dates and month labels', () {
      expect(localDate(DateTime(2026, 3, 7)), '2026-03-07');
      expect(localMonth(DateTime(2026, 12, 31)), '2026-12');
      expect(monthLabel('2026-10'), 'October 2026');
      expect(monthLabel('2026-10', withYear: false), 'October');
      expect(parseNum('12.5abc'), 12.5);
      expect(parseNum(null), isNull);
    });
    test('LineItem.total falls back to price × quantity', () {
      expect(LineItem.fromMap({'name': 'a', 'price': '2', 'quantity': 3}).total, 6);
      expect(LineItem.fromMap({'name': 'a', 'price': 2, 'totalPrice': 5}).total, 5);
    });
  });
}
