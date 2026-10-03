// Read-side models over the same Firestore documents the web app uses.
// Parsing is forgiving (older docs may store numbers as strings or omit fields),
// mirroring the web's parseFloat(...) || 0 handling.
import '../core/utils.dart';

double _num(Object? v, [double fallback = 0]) => parseNum(v) ?? fallback;
String _s(Object? v, [String fallback = '']) => v is String ? v : (v == null ? fallback : '$v');

class LineItem {
  const LineItem({required this.name, required this.category, required this.quantity, required this.price, this.totalPrice});

  final String name;
  final String category;
  final double quantity;
  final double price;
  final double? totalPrice;

  factory LineItem.fromMap(Map m) => LineItem(
        name: _s(m['name'] ?? m['description'], 'Unknown Item'),
        category: _s(m['category'], 'Other'),
        quantity: _num(m['quantity'], 1),
        price: _num(m['price']),
        totalPrice: parseNum(m['totalPrice']),
      );

  /// Line-item total; older entries may only have a unit price (web: itemTotal).
  double get total => totalPrice ?? price * (quantity == 0 ? 1 : quantity);

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'quantity': quantity,
        'price': price,
        if (totalPrice != null) 'totalPrice': totalPrice,
      };
}

class Txn {
  const Txn({
    required this.id,
    required this.merchant,
    required this.date,
    required this.total,
    required this.lineItems,
    required this.source,
    required this.type,
    this.location,
    this.splitId,
    this.createdAt,
    this.category,
    required this.raw,
  });

  final String id;
  final String merchant;
  final String date; // YYYY-MM-DD
  final double total;
  final List<LineItem> lineItems;
  final String source; // scan | manual | split
  final String type; // expense | refund
  final String? location;
  final String? splitId;
  final String? createdAt;
  final String? category; // legacy top-level category
  final Map<String, dynamic> raw;

  bool get isRefund => type == 'refund';
  bool get isSplit => source == 'split';
  String get month => date.length >= 7 ? date.substring(0, 7) : date;
  String get firstCategory => lineItems.isNotEmpty ? lineItems.first.category : 'General';

  factory Txn.fromMap(String id, Map<String, dynamic> m) => Txn(
        id: id,
        merchant: _s(m['merchant']),
        date: _s(m['date']),
        total: _num(m['total']),
        lineItems: (m['lineItems'] is List) ? (m['lineItems'] as List).whereType<Map>().map(LineItem.fromMap).toList() : const [],
        source: _s(m['source'], 'manual'),
        type: _s(m['type'], 'expense'),
        location: m['location'] is String && (m['location'] as String).isNotEmpty ? m['location'] as String : null,
        splitId: m['splitId'] as String?,
        createdAt: m['createdAt'] as String?,
        category: m['category'] as String?,
        raw: m,
      );
}

class UserSettings {
  const UserSettings(this.raw);
  final Map<String, dynamic> raw;

  String? get currency => raw['currency'] as String?;
  double get income => _num(raw['income']);
  bool get hasIncome => income != 0;
  String get savingsType => _s(raw['savingsType'], 'percentage');
  double get savingsValue => _num(raw['savingsValue']);
  bool get aiInsights => raw['aiInsights'] == true;

  /// Raw string form for editable inputs ("" when unset).
  String get incomeText => raw['income'] == null || raw['income'] == '' ? '' : '${raw['income']}';
  String get savingsValueText => raw['savingsValue'] == null || raw['savingsValue'] == '' ? '' : '${raw['savingsValue']}';
}

class GroupMember {
  const GroupMember({required this.userId, this.displayName = '', this.email = '', this.photoURL = ''});
  final String userId;
  final String displayName;
  final String email;
  final String photoURL;

  factory GroupMember.fromMap(Map m) => GroupMember(
        userId: _s(m['userId']),
        displayName: _s(m['displayName']),
        email: _s(m['email']),
        photoURL: _s(m['photoURL']),
      );

  Map<String, dynamic> toMap() => {'userId': userId, 'displayName': displayName, 'email': email, 'photoURL': photoURL};

  String get label => displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email : 'Member');
}

class Group {
  const Group({required this.id, required this.name, required this.createdBy, required this.memberIds, required this.members, this.createdAt});
  final String id;
  final String name;
  final String createdBy;
  final List<String> memberIds;
  final List<GroupMember> members;
  final String? createdAt;

  factory Group.fromMap(String id, Map<String, dynamic> m) => Group(
        id: id,
        name: _s(m['name']),
        createdBy: _s(m['createdBy']),
        memberIds: (m['memberIds'] as List? ?? const []).map((e) => '$e').toList(),
        members: (m['members'] as List? ?? const []).whereType<Map>().map(GroupMember.fromMap).toList(),
        createdAt: m['createdAt'] as String?,
      );
}

class SplitParticipant {
  const SplitParticipant({required this.userId, this.displayName = '', this.photoURL = '', required this.amount, this.status = 'pending'});
  final String userId;
  final String displayName;
  final String photoURL;
  final double amount;
  final String status;

  bool get settled => status == 'settled';

  factory SplitParticipant.fromMap(Map m) => SplitParticipant(
        userId: _s(m['userId']),
        displayName: _s(m['displayName']),
        photoURL: _s(m['photoURL']),
        amount: _num(m['amount']),
        status: _s(m['status'], 'pending'),
      );
}

class GroupSplit {
  const GroupSplit({
    required this.id,
    required this.groupId,
    required this.payerId,
    required this.merchant,
    required this.date,
    required this.totalAmount,
    required this.participants,
    required this.shares,
    this.createdAt,
  });

  final String id;
  final String groupId;
  final String payerId;
  final String merchant;
  final String date;
  final double totalAmount;
  final List<SplitParticipant> participants;
  final Map<String, double> shares;
  final String? createdAt;

  factory GroupSplit.fromMap(String id, Map<String, dynamic> m) => GroupSplit(
        id: id,
        groupId: _s(m['groupId']),
        payerId: _s(m['payerId']),
        merchant: _s(m['merchant']),
        date: _s(m['date']),
        totalAmount: _num(m['totalAmount']),
        participants: (m['participants'] as List? ?? const []).whereType<Map>().map(SplitParticipant.fromMap).toList(),
        shares: {for (final e in (m['shares'] as Map? ?? const {}).entries) '${e.key}': _num(e.value)},
        createdAt: m['createdAt'] as String?,
      );

  SplitParticipant? participant(String uid) {
    for (final p in participants) {
      if (p.userId == uid) return p;
    }
    return null;
  }

  String get payerName => participant(payerId)?.displayName ?? '';
}

class AppNotification {
  const AppNotification({required this.id, required this.raw});
  final String id;
  final Map<String, dynamic> raw;

  String get type => _s(raw['type']);
  String get groupId => _s(raw['groupId']);
  String get groupName => _s(raw['groupName']);
  String get splitId => _s(raw['splitId']);
  String get payerName => _s(raw['payerName']);
  String get addedByName => _s(raw['addedByName']);
  String get merchant => _s(raw['merchant']);
  double get amount => _num(raw['amount']);
  String get createdAt => _s(raw['createdAt']);
}

class UserProfile {
  const UserProfile({required this.userId, this.displayName = '', this.email = '', this.photoURL = ''});
  final String userId;
  final String displayName;
  final String email;
  final String photoURL;

  factory UserProfile.fromMap(String id, Map<String, dynamic> m) =>
      UserProfile(userId: id, displayName: _s(m['displayName']), email: _s(m['email']), photoURL: _s(m['photoURL']));

  GroupMember toMember() => GroupMember(userId: userId, displayName: displayName, email: email, photoURL: photoURL);
}
