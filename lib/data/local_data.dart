import 'package:shared_preferences/shared_preferences.dart';

/// Device-stored data tied to a signed-in user (web: src/lib/localData.js).
/// Cleared on sign-out and account deletion; theme is device-level and kept.
class LocalData {
  LocalData(this._prefs);
  final SharedPreferences _prefs;

  static const _userKeyPrefixes = ['insights_', 'rateLimit_'];

  static String insightsCacheKey(String uid, String monthKey) => 'insights_${uid}_$monthKey';

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);

  Future<void> clearUserData() async {
    for (final key in _prefs.getKeys().toList()) {
      if (_userKeyPrefixes.any(key.startsWith)) await _prefs.remove(key);
    }
  }
}
