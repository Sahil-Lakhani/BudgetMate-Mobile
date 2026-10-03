// Pure balance math over split documents (port of src/lib/balances.js).
// Settled shares contribute nothing.
import '../data/models.dart';

double round2(double n) => (n * 100).round() / 100;

class MemberBalance {
  MemberBalance(this.displayName, this.amount);
  String displayName;
  double amount; // positive = they owe me, negative = I owe them
}

class Balances {
  const Balances({required this.youOwe, required this.owedToYou, required this.net, required this.byMember});
  final double youOwe;
  final double owedToYou;
  final double net;
  final Map<String, MemberBalance> byMember;
}

Balances computeBalances(List<GroupSplit> splits, String me) {
  var youOwe = 0.0, owedToYou = 0.0;
  final byMember = <String, MemberBalance>{};

  void add(String userId, String? displayName, double delta) {
    final b = byMember.putIfAbsent(userId, () => MemberBalance(displayName ?? '', 0));
    b.amount += delta;
    if ((displayName ?? '').isNotEmpty && b.displayName.isEmpty) b.displayName = displayName!;
  }

  for (final s in splits) {
    if (s.payerId == me) {
      for (final p in s.participants) {
        if (p.userId == me || p.settled) continue;
        owedToYou += p.amount;
        add(p.userId, p.displayName, p.amount);
      }
    } else {
      final mine = s.participant(me);
      if (mine == null || mine.settled) continue;
      youOwe += mine.amount;
      add(s.payerId, s.participant(s.payerId)?.displayName, -mine.amount);
    }
  }

  byMember.removeWhere((_, b) {
    b.amount = round2(b.amount);
    return b.amount == 0;
  });
  youOwe = round2(youOwe);
  owedToYou = round2(owedToYou);
  return Balances(youOwe: youOwe, owedToYou: owedToYou, net: round2(owedToYou - youOwe), byMember: byMember);
}

/// Splits [total] into [count] equal shares; the rounding remainder goes to
/// [remainderIndex] (the payer), falling back to the first share.
List<double> distributeEvenly(double total, int count, [int remainderIndex = 0]) {
  if (count == 0) return const [];
  final base = ((total * 100) / count).floor() / 100;
  final remainder = round2(total - base * count);
  final target = remainderIndex >= 0 && remainderIndex < count ? remainderIndex : 0;
  return List.generate(count, (i) => i == target ? round2(base + remainder) : base);
}
