import 'package:shared_preferences/shared_preferences.dart';

class PendingInviteStore {
  static const _kToken = 'pendingInviteToken';

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kToken);
    if (t == null) return null;
    final v = t.trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
  }
}
