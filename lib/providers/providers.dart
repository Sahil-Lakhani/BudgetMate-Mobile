// App-wide state. Replaces the web's AuthContext, ThemeContext and CurrencyContext.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/currency.dart' as cur;
import '../core/rate_limit.dart';
import '../data/account_service.dart';
import '../data/auth_service.dart';
import '../data/firestore_service.dart';
import '../data/gemini_service.dart';
import '../data/local_data.dart';
import '../data/models.dart';

// ─── Services ────────────────────────────────────────────────────────────────

/// Overridden in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final localDataProvider = Provider((ref) => LocalData(ref.watch(sharedPrefsProvider)));
final rateLimiterProvider = Provider((ref) => RateLimiter(ref.watch(sharedPrefsProvider)));

final firestoreServiceProvider =
    Provider((ref) => FirestoreService(FirebaseFirestore.instance, ref.watch(rateLimiterProvider)));

final authServiceProvider = Provider((ref) => AuthService(FirebaseAuth.instance, ref.watch(localDataProvider)));

final geminiServiceProvider = Provider((ref) => GeminiService(FirebaseAuth.instance, ref.watch(rateLimiterProvider)));

final accountServiceProvider = Provider((ref) => AccountService(
      FirebaseFirestore.instance,
      FirebaseAuth.instance,
      ref.watch(authServiceProvider),
      ref.watch(localDataProvider),
    ));

// ─── Auth ────────────────────────────────────────────────────────────────────

final authStateProvider = StreamProvider<User?>((ref) => ref.watch(authServiceProvider).authStateChanges());

final currentUserProvider = Provider<User?>((ref) => ref.watch(authStateProvider).value);

/// The signed-in uid; screens behind the auth guard can rely on it.
final uidProvider = Provider<String?>((ref) => ref.watch(currentUserProvider)?.uid);

// ─── Data streams ────────────────────────────────────────────────────────────

/// All of the user's transactions, newest first (live).
final transactionsProvider = StreamProvider<List<Txn>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).watchUserTransactions(uid);
});

final settingsProvider = StreamProvider<UserSettings?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUserSettings(uid);
});

final unreadNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).watchUnreadNotifications(uid);
});

final groupsProvider = StreamProvider<List<Group>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).watchUserGroups(uid);
});

final groupProvider = StreamProvider.family<Group?, String>(
    (ref, groupId) => ref.watch(firestoreServiceProvider).watchGroup(groupId));

final groupSplitsProvider = StreamProvider.family<List<GroupSplit>, String>(
    (ref, groupId) => ref.watch(firestoreServiceProvider).watchGroupSplits(groupId));

final splitProvider =
    StreamProvider.family<GroupSplit?, String>((ref, splitId) => ref.watch(firestoreServiceProvider).watchSplit(splitId));

// ─── Currency (web: CurrencyContext) ─────────────────────────────────────────

/// Selected currency code, synced to users/{uid}.settings.currency.
final currencyProvider = Provider<String>((ref) => ref.watch(settingsProvider).value?.currency ?? 'EUR');

/// formatCurrency bound to the user's currency.
final formatCurrencyProvider = Provider<String Function(Object?)>((ref) {
  final code = ref.watch(currencyProvider);
  return (amount) => cur.formatCurrency(amount, code);
});

// ─── Theme (web: ThemeContext, stored under the same "theme" key) ────────────

class ThemeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme';

  @override
  ThemeMode build() {
    final stored = ref.watch(sharedPrefsProvider).getString(_key);
    if (stored == 'dark') return ThemeMode.dark;
    if (stored == 'light') return ThemeMode.light;
    return ThemeMode.dark; // dark is the default until the user picks light on the Profile page
  }

  bool get isDark => state == ThemeMode.dark;

  void setDark(bool dark) {
    state = dark ? ThemeMode.dark : ThemeMode.light;
    ref.read(sharedPrefsProvider).setString(_key, dark ? 'dark' : 'light');
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
