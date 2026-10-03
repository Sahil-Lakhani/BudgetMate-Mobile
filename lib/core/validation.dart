// Dart port of the web app's Zod schemas (src/lib/validation.js).
// Each validator returns the normalized map that is written to Firestore — the same
// shape the web app writes — or throws [ValidationError].
import 'errors.dart';

const groupMemberLimit = 20;
final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// z.coerce.number(): Number(x). '' → 0, null → 0, unparsable → error.
double _coerceNum(Object? v, String field) {
  if (v is num) {
    if (v.isFinite) return v.toDouble();
  } else if (v == null) {
    return 0;
  } else if (v is bool) {
    return v ? 1 : 0;
  } else if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    final p = double.tryParse(t);
    if (p != null && p.isFinite) return p;
  }
  throw ValidationError('$field must be a number');
}

/// Writes whole numbers as ints so Firestore docs look the same as the web's (1, not 1.0).
num _clean(double v) => v == v.roundToDouble() && v.abs() < 9e15 ? v.toInt() : v;

String _str(Object? v, String field, {String? def, bool trim = false}) {
  if (v == null && def != null) return def;
  if (v is! String) throw ValidationError('$field must be text');
  return trim ? v.trim() : v;
}

Map<String, dynamic> validateTransactionItem(Map item) {
  final name = _str(item['name'], 'Item name');
  if (name.isEmpty) throw const ValidationError('Item name is required');
  final quantity = item['quantity'] == null ? 1.0 : _coerceNum(item['quantity'], 'Quantity');
  if (quantity <= 0) throw const ValidationError('Quantity must be positive');
  final price = _coerceNum(item['price'], 'Price');
  if (price < 0) throw const ValidationError('Price must be non-negative');
  final out = <String, dynamic>{
    'name': name,
    'category': _str(item['category'], 'Category', def: 'Other'),
    'quantity': _clean(quantity),
    'price': _clean(price),
  };
  if (item['totalPrice'] != null) {
    final tp = _coerceNum(item['totalPrice'], 'Total price');
    if (tp < 0) throw const ValidationError('Total price must be non-negative');
    out['totalPrice'] = _clean(tp);
  }
  return out;
}

Map<String, dynamic> validateTransaction(Map data) {
  final merchant = _str(data['merchant'], 'Merchant name');
  if (merchant.isEmpty) throw const ValidationError('Merchant name is required');
  final total = _coerceNum(data['total'], 'Total');
  final date = _str(data['date'], 'Date');
  if (!_dateRe.hasMatch(date)) throw const ValidationError('Date must be in YYYY-MM-DD format');
  final rawItems = data['lineItems'] ?? const [];
  if (rawItems is! List) throw const ValidationError('Line items must be a list');
  final lineItems = rawItems.map((i) => validateTransactionItem(i as Map)).toList();
  final source = _str(data['source'], 'Source', def: 'scan');
  if (!const ['scan', 'manual', 'split'].contains(source)) throw const ValidationError('Invalid source');
  final type = _str(data['type'], 'Type', def: 'expense');
  if (!const ['expense', 'refund'].contains(type)) throw const ValidationError('Invalid type');

  if (type == 'refund' ? total >= 0 : total < 0) {
    throw const ValidationError('Expenses must be non-negative; refunds must be negative');
  }
  if (type != 'refund' && lineItems.isEmpty) throw const ValidationError('At least one item is required');

  final out = <String, dynamic>{'merchant': merchant};
  if (data['location'] != null) out['location'] = _str(data['location'], 'Location');
  out.addAll({'total': _clean(total), 'date': date, 'lineItems': lineItems, 'source': source, 'type': type});
  if (data['splitId'] != null) out['splitId'] = _str(data['splitId'], 'splitId');
  if (data['createdAt'] != null) out['createdAt'] = _str(data['createdAt'], 'createdAt');
  return out;
}

/// Passthrough: unknown keys (income, savingsType, aiInsights, …) are kept.
Map<String, dynamic> validateUserSettings(Map data) {
  final out = Map<String, dynamic>.from(data);
  out['currency'] = _str(data['currency'], 'Currency', def: 'EUR');
  out['language'] = _str(data['language'], 'Language', def: 'en');
  final n = data['notifications'];
  if (n != null && n is! bool) throw const ValidationError('notifications must be true/false');
  out['notifications'] = n ?? true;
  return out;
}

Map<String, dynamic> validateGroupMember(Map m) {
  final userId = _str(m['userId'], 'Member userId');
  if (userId.isEmpty) throw const ValidationError('Member userId is required');
  return {
    'userId': userId,
    'displayName': _str(m['displayName'], 'displayName', def: ''),
    'email': _str(m['email'], 'email', def: ''),
    'photoURL': _str(m['photoURL'], 'photoURL', def: ''),
  };
}

Map<String, dynamic> validateGroup(Map g) {
  final name = _str(g['name'], 'Group name', trim: true);
  if (name.isEmpty) throw const ValidationError('Group name is required');
  if (name.length > 60) throw const ValidationError('Group name is too long');
  final raw = g['members'];
  if (raw is! List || raw.isEmpty) throw const ValidationError('At least one member is required');
  if (raw.length > groupMemberLimit) throw const ValidationError('Groups are limited to $groupMemberLimit members');
  final members = raw.map((m) => validateGroupMember(m as Map)).toList();
  if (members.map((m) => m['userId']).toSet().length != members.length) {
    throw const ValidationError('A member can only be added once');
  }
  return {'name': name, 'members': members};
}

Map<String, dynamic> validateSplitParticipant(Map p) {
  final userId = _str(p['userId'], 'Participant userId');
  if (userId.isEmpty) throw const ValidationError('Participant userId is required');
  final amount = _coerceNum(p['amount'], 'Share');
  if (amount < 0) throw const ValidationError('Share must be non-negative');
  final status = _str(p['status'], 'status', def: 'pending');
  if (!const ['pending', 'settled'].contains(status)) throw const ValidationError('Invalid status');
  return {
    'userId': userId,
    'displayName': _str(p['displayName'], 'displayName', def: ''),
    'photoURL': _str(p['photoURL'], 'photoURL', def: ''),
    'amount': _clean(amount),
    'status': status,
  };
}

Map<String, dynamic> validateSplit(Map s) {
  final groupId = _str(s['groupId'], 'groupId');
  if (groupId.isEmpty) throw const ValidationError('groupId is required');
  final payerId = _str(s['payerId'], 'payerId');
  if (payerId.isEmpty) throw const ValidationError('payerId is required');
  final merchant = _str(s['merchant'], 'Merchant name', trim: true);
  if (merchant.isEmpty) throw const ValidationError('Merchant name is required');
  final date = _str(s['date'], 'Date');
  if (!_dateRe.hasMatch(date)) throw const ValidationError('Date must be in YYYY-MM-DD format');
  final totalAmount = _coerceNum(s['totalAmount'], 'Total');
  if (totalAmount <= 0) throw const ValidationError('Total must be greater than zero');
  final raw = s['participants'];
  if (raw is! List || raw.isEmpty) throw const ValidationError('At least one participant is required');
  if (raw.length > 20) throw const ValidationError('Too many participants');
  final participants = raw.map((p) => validateSplitParticipant(p as Map)).toList();

  final sum = participants.fold<double>(0, (a, p) => a + (p['amount'] as num).toDouble());
  if ((sum - totalAmount).abs() >= 0.005) throw const ValidationError('Participant shares must add up to the total');
  if (!participants.any((p) => p['userId'] == payerId)) throw const ValidationError('Payer must be a participant');

  return {
    'groupId': groupId,
    'payerId': payerId,
    'merchant': merchant,
    'date': date,
    'totalAmount': _clean(totalAmount),
    'participants': participants,
  };
}

Map<String, dynamic> validateNotification(Map n) {
  switch (n['type']) {
    case 'split_added':
      final splitId = _str(n['splitId'], 'splitId');
      final groupId = _str(n['groupId'], 'groupId');
      if (splitId.isEmpty || groupId.isEmpty) throw const ValidationError('Invalid notification');
      final amount = _coerceNum(n['amount'], 'amount');
      if (amount < 0) throw const ValidationError('Invalid notification amount');
      return {
        'type': 'split_added',
        'splitId': splitId,
        'groupId': groupId,
        'groupName': _str(n['groupName'], 'groupName', def: ''),
        'payerName': _str(n['payerName'], 'payerName', def: ''),
        'merchant': _str(n['merchant'], 'merchant', def: ''),
        'amount': _clean(amount),
      };
    case 'group_added':
      final groupId = _str(n['groupId'], 'groupId');
      if (groupId.isEmpty) throw const ValidationError('Invalid notification');
      return {
        'type': 'group_added',
        'groupId': groupId,
        'groupName': _str(n['groupName'], 'groupName', def: ''),
        'addedByName': _str(n['addedByName'], 'addedByName', def: ''),
      };
    default:
      throw const ValidationError('Invalid notification type');
  }
}
