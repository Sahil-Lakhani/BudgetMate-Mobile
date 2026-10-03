// 1:1 port of the web app's src/lib/firestore.js — same collections, same document
// shapes, same ids — so the phone and the website share one dataset under the same rules.
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/rate_limit.dart';
import '../core/utils.dart';
import '../core/validation.dart';
import 'models.dart';

/// Errors thrown with these messages are safe to show verbatim (web: GROUP_ERRORS).
abstract final class GroupErrors {
  static const notFound = 'Group not found';
  static const alreadyMember = 'Already a member of this group';
  static const full = 'Groups are limited to $groupMemberLimit members';
}

class GroupError implements Exception {
  const GroupError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

/// Split-related ledger entries use fixed ids so retries can never double-write.
String splitTxId(String splitId, [String? participantId]) => participantId != null ? 'split-$splitId-$participantId' : 'split-$splitId';

List<Map<String, dynamic>> _splitLineItems(String merchant, num amount, [List<Map<String, dynamic>>? lineItems]) =>
    (lineItems != null && lineItems.isNotEmpty)
    ? lineItems
    : [
        {'name': merchant, 'price': amount, 'quantity': 1, 'totalPrice': amount, 'category': 'Other'},
      ];

int _byCreatedDesc(String? a, String? b) =>
    (DateTime.tryParse(b ?? '') ?? DateTime(0)).compareTo(DateTime.tryParse(a ?? '') ?? DateTime(0));

int _byDateDesc(Txn a, Txn b) => (DateTime.tryParse(b.date) ?? DateTime(0)).compareTo(DateTime.tryParse(a.date) ?? DateTime(0));

class FirestoreService {
  FirestoreService(this._db, this._limiter);

  final FirebaseFirestore _db;
  final RateLimiter _limiter;

  CollectionReference<Map<String, dynamic>> _txCol(String uid) => _db.collection('users').doc(uid).collection('transactions');
  CollectionReference<Map<String, dynamic>> _notifCol(String uid) => _db.collection('users').doc(uid).collection('notifications');

  // ─── Transactions ───────────────────────────────────────────────────────────

  Future<List<Txn>> getUserTransactions(String uid) async {
    final snap = await _txCol(uid).get();
    return snap.docs.map((d) => Txn.fromMap(d.id, d.data())).toList()..sort(_byDateDesc);
  }

  /// Live version of [getUserTransactions], newest first.
  /// An empty answer from the local cache (e.g. right after sign-in) is skipped so the UI
  /// never flashes "no transactions" before the server responds.
  Stream<List<Txn>> watchUserTransactions(String uid) =>
      _txCol(uid)
          .snapshots(includeMetadataChanges: true)
          .where((snap) => snap.docs.isNotEmpty || !snap.metadata.isFromCache)
          .map((snap) => snap.docs.map((d) => Txn.fromMap(d.id, d.data())).toList()..sort(_byDateDesc));

  Future<void> saveUser(User user) async {
    final publicData = {
      'email': user.email,
      'displayName': user.displayName ?? '',
      'photoURL': user.photoURL ?? '',
      'lastUpdated': _nowIso(),
    };
    await _db.collection('userProfiles').doc(user.uid).set(publicData, SetOptions(merge: true));
    await _db.collection('users').doc(user.uid).set(publicData, SetOptions(merge: true));
  }

  Future<String> saveTransaction(String uid, Map<String, dynamic> data) async {
    _limiter.check('firestore-write');
    final validated = validateTransaction(data);
    final ref = await _txCol(uid).add({...validated, 'createdAt': _nowIso(), 'source': validated['source'] ?? 'scan'});
    return ref.id;
  }

  Future<Txn?> getTransaction(String uid, String id) async {
    final snap = await _txCol(uid).doc(id).get();
    return snap.exists ? Txn.fromMap(snap.id, snap.data()!) : null;
  }

  Future<void> deleteTransaction(String uid, String id) => _txCol(uid).doc(id).delete();

  // ─── Settings ───────────────────────────────────────────────────────────────

  Future<UserSettings?> getUserSettings(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final s = snap.data()?['settings'];
    return s is Map ? UserSettings(Map<String, dynamic>.from(s)) : null;
  }

  /// "No settings" is only trusted once the server confirms it. A cache-only answer (or the
  /// local profile write made at sign-in) would wrongly trigger onboarding.
  Stream<UserSettings?> watchUserSettings(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .where((snap) => !snap.metadata.isFromCache || snap.data()?['settings'] is Map)
      .map((snap) {
        final s = snap.data()?['settings'];
        return s is Map ? UserSettings(Map<String, dynamic>.from(s)) : null;
      });

  Future<void> updateUserSettings(String uid, Map<String, dynamic> settings) async {
    _limiter.check('firestore-write');
    final ref = _db.collection('users').doc(uid);
    final existing = await ref.get();
    final current = (existing.data()?['settings'] as Map?) ?? const {};
    final validated = validateUserSettings({...current, ...settings});
    await ref.set({'settings': validated}, SetOptions(merge: true));
  }

  // ─── Groups ─────────────────────────────────────────────────────────────────

  Future<String> createGroup(String uid, {required String name, required List<GroupMember> members}) async {
    _limiter.check('firestore-write');
    final validated = validateGroup({'name': name, 'members': members.map((m) => m.toMap()).toList()});
    final all = validated['members'] as List<Map<String, dynamic>>;
    if (!all.any((m) => m['userId'] == uid)) throw Exception('Group creator must be included in members');

    final ref = await _db.collection('groups').add({
      'name': validated['name'],
      'createdBy': uid,
      'memberIds': all.map((m) => m['userId']).toList(),
      'members': all,
      'createdAt': _nowIso(),
    });
    return ref.id;
  }

  Future<List<Group>> getUserGroups(String uid) async {
    final snap = await _db.collection('groups').where('memberIds', arrayContains: uid).get();
    return snap.docs.map((d) => Group.fromMap(d.id, d.data())).toList();
  }

  Stream<List<Group>> watchUserGroups(String uid) => _db
      .collection('groups')
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map((d) => Group.fromMap(d.id, d.data())).toList());

  Future<Group?> getGroup(String groupId) async {
    final snap = await _db.collection('groups').doc(groupId).get();
    return snap.exists ? Group.fromMap(snap.id, snap.data()!) : null;
  }

  Stream<Group?> watchGroup(String groupId) =>
      _db.collection('groups').doc(groupId).snapshots().map((s) => s.exists ? Group.fromMap(s.id, s.data()!) : null);

  /// Adds [member] in a transaction so concurrent adds can't overwrite each other.
  Future<List<GroupMember>> addMemberToGroup(String groupId, GroupMember member) async {
    _limiter.check('firestore-write');
    final validated = validateGroupMember(member.toMap());
    final ref = _db.collection('groups').doc(groupId);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw const GroupError(GroupErrors.notFound);
      final data = snap.data()!;
      final members = List<Map<String, dynamic>>.from(
        (data['members'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final memberIds = List<String>.from((data['memberIds'] as List? ?? const []).map((e) => '$e'));
      if (memberIds.contains(validated['userId'])) throw const GroupError(GroupErrors.alreadyMember);
      if (memberIds.length >= groupMemberLimit) throw const GroupError(GroupErrors.full);

      final next = [...members, validated];
      tx.update(ref, {
        'members': next,
        'memberIds': [...memberIds, validated['userId']],
      });
      return next.map(GroupMember.fromMap).toList();
    });
  }

  Future<void> leaveGroup(String groupId, String uid) async {
    _limiter.check('firestore-write');
    final ref = _db.collection('groups').doc(groupId);
    final snap = await ref.get();
    if (!snap.exists) throw const GroupError(GroupErrors.notFound);
    final data = snap.data()!;
    await ref.set({
      'members': (data['members'] as List? ?? const []).where((m) => (m as Map)['userId'] != uid).toList(),
      'memberIds': (data['memberIds'] as List? ?? const []).where((id) => id != uid).toList(),
    }, SetOptions(merge: true));
  }

  /// Creator only (enforced by rules). Removes the group and every split in it.
  Future<void> deleteGroup(String groupId) async {
    _limiter.check('firestore-write');
    final splits = await _db.collection('splits').where('groupId', isEqualTo: groupId).get();
    final batch = _db.batch();
    for (final d in splits.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_db.collection('groups').doc(groupId));
    await batch.commit();
  }

  // ─── Splits ─────────────────────────────────────────────────────────────────

  /// Create-only write; "already exists" means a previous attempt succeeded.
  Future<void> _createSplitTransaction(String uid, String txId, Map<String, dynamic> data) async {
    final validated = validateTransaction(data);
    final ref = _txCol(uid).doc(txId);
    try {
      await ref.set({...validated, 'createdAt': _nowIso()});
    } catch (_) {
      // Cross-user writes are create-only, so a retry surfaces as permission-denied;
      // rules allow reading exactly this doc back to confirm it is already there.
      DocumentSnapshot? existing;
      try {
        existing = await ref.get();
      } catch (_) {}
      if (existing?.exists ?? false) return;
      rethrow;
    }
  }

  Future<({String splitId, String shareToken})> createSplit(
    String groupId,
    String payerId, {
    required String merchant,
    required String date,
    required num totalAmount,
    required List<Map<String, dynamic>> participants,
    List<Map<String, dynamic>>? lineItems,
  }) async {
    _limiter.check('firestore-write');
    final validated = validateSplit({
      'groupId': groupId,
      'payerId': payerId,
      'merchant': merchant,
      'date': date,
      'totalAmount': totalAmount,
      'participants': participants,
    });

    final rnd = Random.secure();
    final shareToken = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

    final vParticipants = validated['participants'] as List<Map<String, dynamic>>;
    final shares = {for (final p in vParticipants) p['userId'] as String: p['amount']};
    // The payer covered the whole bill, so their own share is settled from the start
    final withPayer = vParticipants.map((p) => p['userId'] == payerId ? {...p, 'status': 'settled'} : p).toList();

    final splitData = {
      ...validated,
      'participants': withPayer,
      'participantIds': vParticipants.map((p) => p['userId']).toList(),
      'shares': shares,
      'shareToken': shareToken,
      'createdAt': _nowIso(),
    };

    final ref = _db.collection('splits').doc();
    final payerTx = validateTransaction({
      'merchant': validated['merchant'],
      'date': validated['date'],
      'total': validated['totalAmount'],
      'lineItems': _splitLineItems(validated['merchant'] as String, validated['totalAmount'] as num, lineItems),
      'source': 'split',
      'type': 'expense',
      'splitId': ref.id,
    });

    final batch = _db.batch();
    batch.set(ref, splitData);
    batch.set(_txCol(payerId).doc(splitTxId(ref.id)), {...payerTx, 'createdAt': _nowIso()});
    await batch.commit();
    return (splitId: ref.id, shareToken: shareToken);
  }

  Future<List<GroupSplit>> getGroupSplits(String groupId) async {
    final snap = await _db.collection('splits').where('groupId', isEqualTo: groupId).get();
    return snap.docs.map((d) => GroupSplit.fromMap(d.id, d.data())).toList()..sort((a, b) => _byCreatedDesc(a.createdAt, b.createdAt));
  }

  /// Live splits for one group, newest first.
  Stream<List<GroupSplit>> watchGroupSplits(String groupId) => _db
      .collection('splits')
      .where('groupId', isEqualTo: groupId)
      .snapshots()
      .map((s) => s.docs.map((d) => GroupSplit.fromMap(d.id, d.data())).toList()..sort((a, b) => _byCreatedDesc(a.createdAt, b.createdAt)));

  /// Live splits across many groups ("in" allows 30 values per query).
  Stream<List<GroupSplit>> watchSplitsForGroups(List<String> groupIds) {
    if (groupIds.isEmpty) return Stream.value(const []);
    final chunks = <List<String>>[];
    for (var i = 0; i < groupIds.length; i += 30) {
      chunks.add(groupIds.sublist(i, min(i + 30, groupIds.length)));
    }
    final perChunk = List<List<GroupSplit>?>.filled(chunks.length, null);
    late StreamController<List<GroupSplit>> controller;
    final subs = <StreamSubscription>[];
    controller = StreamController<List<GroupSplit>>(
      onListen: () {
        for (var i = 0; i < chunks.length; i++) {
          subs.add(
            _db.collection('splits').where('groupId', whereIn: chunks[i]).snapshots().listen((snap) {
              perChunk[i] = snap.docs.map((d) => GroupSplit.fromMap(d.id, d.data())).toList();
              controller.add(perChunk.expand((c) => c ?? const <GroupSplit>[]).toList());
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<GroupSplit?> getSplit(String splitId) async {
    final snap = await _db.collection('splits').doc(splitId).get();
    return snap.exists ? GroupSplit.fromMap(snap.id, snap.data()!) : null;
  }

  Stream<GroupSplit?> watchSplit(String splitId) =>
      _db.collection('splits').doc(splitId).snapshots().map((s) => s.exists ? GroupSplit.fromMap(s.id, s.data()!) : null);

  /// Marks [uid]'s share settled, then records it in both ledgers.
  Future<void> settleSplit(String splitId, String uid) async {
    _limiter.check('firestore-write');
    final ref = _db.collection('splits').doc(splitId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Split not found');
    final split = GroupSplit.fromMap(snap.id, snap.data()!);
    final share = split.participant(uid);
    if (share == null) throw Exception('Not a participant of this split');

    // Ledger entries first (fixed ids → idempotent), then flip the status.
    if (uid != split.payerId) await _recordSettlementInLedgers(splitId, split, share, uid);

    await _db.runTransaction((tx) async {
      final fresh = await tx.get(ref);
      if (!fresh.exists) throw Exception('Split not found');
      final participants = (fresh.data()!['participants'] as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();
      final mine = participants.where((p) => p['userId'] == uid);
      if (mine.isNotEmpty && mine.first['status'] == 'settled') return;
      tx.update(ref, {
        'participants': participants.map((p) => p['userId'] == uid ? {...p, 'status': 'settled'} : p).toList(),
      });
    });
  }

  Future<void> _recordSettlementInLedgers(String splitId, GroupSplit split, SplitParticipant share, String uid) async {
    final today = localDate();
    final num amount = split.shares[uid] ?? share.amount;
    final txId = splitTxId(splitId, uid);
    final payerName = split.payerName.isNotEmpty ? split.payerName : 'payer';

    await _createSplitTransaction(uid, txId, {
      'merchant': split.merchant,
      'date': today,
      'total': amount,
      'lineItems': _splitLineItems('${split.merchant} — your share (paid to $payerName)', amount),
      'source': 'split',
      'type': 'expense',
      'splitId': splitId,
    });

    await _createSplitTransaction(split.payerId, txId, {
      'merchant': '${split.merchant} — repaid by ${share.displayName.isNotEmpty ? share.displayName : 'participant'}',
      'date': today,
      'total': -amount,
      'lineItems': const <Map<String, dynamic>>[],
      'source': 'split',
      'type': 'refund',
      'splitId': splitId,
    });
  }

  // ─── User search (public userProfiles only) ─────────────────────────────────

  Future<List<UserProfile>> searchUsersByEmail(String email) async {
    if (email.isEmpty) return const [];
    final snap = await _db.collection('userProfiles').where('email', isEqualTo: email).limit(5).get();
    return snap.docs.map((d) => UserProfile.fromMap(d.id, d.data())).toList();
  }

  Future<List<UserProfile>> searchUsersByName(String name) async {
    if (name.isEmpty) return const [];
    final snap = await _db
        .collection('userProfiles')
        .where('displayName', isGreaterThanOrEqualTo: name)
        .where('displayName', isLessThanOrEqualTo: '$name')
        .limit(5)
        .get();
    return snap.docs.map((d) => UserProfile.fromMap(d.id, d.data())).toList();
  }

  // ─── Notifications (in-app only) ────────────────────────────────────────────

  Future<void> createNotification(String uid, Map<String, dynamic> data) async {
    final validated = validateNotification(data);
    await _notifCol(uid).add({...validated, 'read': false, 'createdAt': _nowIso()});
  }

  Future<List<AppNotification>> getUserNotifications(String uid) async {
    final snap = await _notifCol(uid).where('read', isEqualTo: false).get();
    return snap.docs.map((d) => AppNotification(id: d.id, raw: d.data())).toList();
  }

  /// Live unread notifications (drives the Groups badge).
  Stream<List<AppNotification>> watchUnreadNotifications(String uid) =>
      _notifCol(uid)
          .where('read', isEqualTo: false)
          .snapshots()
          .map((s) => s.docs.map((d) => AppNotification(id: d.id, raw: d.data())).toList());

  Future<void> markNotificationRead(String uid, String notifId) => _notifCol(uid).doc(notifId).set({'read': true}, SetOptions(merge: true));

  Future<void> markAllNotificationsRead(String uid) async {
    final unread = await getUserNotifications(uid);
    await Future.wait(unread.map((n) => markNotificationRead(uid, n.id)));
  }
}
