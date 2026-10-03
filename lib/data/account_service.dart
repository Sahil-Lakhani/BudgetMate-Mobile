// GDPR self-service: data export (Art. 15/20) and account erasure (Art. 17).
// Port of src/lib/account.js.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils.dart';
import 'auth_service.dart';
import 'local_data.dart';

class AccountService {
  AccountService(this._db, this._auth, this._authService, this._localData);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final AuthService _authService;
  final LocalData _localData;

  List<Map<String, dynamic>> _docs(QuerySnapshot<Map<String, dynamic>> s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList();

  Future<Map<String, dynamic>> exportUserData(String uid) async {
    final users = _db.collection('users').doc(uid);
    final (userDoc, profileDoc) = await (users.get(), _db.collection('userProfiles').doc(uid).get()).wait;
    final (transactions, notifications, groups, splits) = await (
      users.collection('transactions').get(),
      users.collection('notifications').get(),
      _db.collection('groups').where('memberIds', arrayContains: uid).get(),
      _db.collection('splits').where('participantIds', arrayContains: uid).get(),
    ).wait;

    return {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'account': {'uid': uid, ...?userDoc.data()},
      'publicProfile': profileDoc.data(),
      'transactions': _docs(transactions),
      'notifications': _docs(notifications),
      'groups': _docs(groups),
      // shareToken is an internal capability string, not personal data
      'splits': _docs(splits).map((s) => {...s}..remove('shareToken')).toList(),
    };
  }

  /// Writes the export to a JSON file and opens the system share sheet (web: download).
  Future<void> exportAndShare(String uid) async {
    final data = await exportUserData(uid);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/budgetmate-export-${localDate()}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: 'BudgetMate data export'));
  }

  Future<void> _deleteAll(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }

  /// Removes the user's own data and the sign-in account. Shared split records stay
  /// with the other group members (see Privacy Policy §5).
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final uid = user.uid;

    // Confirm identity before touching any data
    await _authService.reauthenticate();

    final groups = await _db.collection('groups').where('memberIds', arrayContains: uid).get();
    for (final g in groups.docs) {
      final data = g.data();
      final memberIds = List<String>.from((data['memberIds'] as List? ?? const []).map((e) => '$e'));
      final members = (data['members'] as List? ?? const []);
      if (memberIds.length == 1 && data['createdBy'] == uid) {
        final splits = await _db.collection('splits').where('groupId', isEqualTo: g.id).get();
        await _deleteAll([...splits.docs.map((d) => d.reference), g.reference]);
      } else {
        await g.reference.set({
          'members': members.where((m) => (m as Map)['userId'] != uid).toList(),
          'memberIds': memberIds.where((id) => id != uid).toList(),
        }, SetOptions(merge: true));
      }
    }

    final userRef = _db.collection('users').doc(uid);
    final (transactions, notifications) = await (userRef.collection('transactions').get(), userRef.collection('notifications').get()).wait;
    await _deleteAll([
      ...transactions.docs.map((d) => d.reference),
      ...notifications.docs.map((d) => d.reference),
      _db.collection('userProfiles').doc(uid),
      userRef,
    ]);

    await _localData.clearUserData();
    await user.delete();
  }
}
