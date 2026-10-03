import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'errors.dart';

/// Client-side throttle, same limits and storage key format as the web's rateLimit.js.
class RateLimiter {
  RateLimiter(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const limits = <String, ({int max, int windowMs})>{
    'gemini-analyze': (max: 5, windowMs: 60000),
    'gemini-insights': (max: 3, windowMs: 60000),
    'firestore-write': (max: 20, windowMs: 60000),
  };

  static const keyPrefix = 'rateLimit_';

  /// Throws [UserFacingError] when [action] exceeded its limit; otherwise records the call.
  void check(String action) {
    final config = limits[action];
    if (config == null) return;

    final key = '$keyPrefix$action';
    final now = _now().millisecondsSinceEpoch;
    var stamps = <int>[];
    try {
      final stored = _prefs.getString(key);
      if (stored != null) stamps = (jsonDecode(stored) as List).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      stamps = [];
    }
    stamps = stamps.where((t) => now - t < config.windowMs).toList();

    if (stamps.length >= config.max) {
      final oldest = stamps.reduce((a, b) => a < b ? a : b);
      final wait = ((oldest + config.windowMs - now) / 1000).ceil();
      throw UserFacingError("You're doing that too often. Please wait $wait seconds and try again.");
    }

    stamps.add(now);
    _prefs.setString(key, jsonEncode(stamps));
  }
}
