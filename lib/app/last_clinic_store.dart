import 'package:shared_preferences/shared_preferences.dart';

class LastClinicStore {
  static String _key(String uid) => 'lastClinicId:$uid';

  /// Last clinic for signed-in user (used by ClinicOnboardingGate).
  static Future<String?> getLastClinic(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(uid));
  }

  static Future<void> setLastClinic(String uid, String clinicId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), clinicId);
  }

  static Future<void> clearLastClinic(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Entry screen (pre-auth): "Continue to last clinic"
  // ─────────────────────────────────────────────────────────────────────────

  static const String _entryLastKey = 'lastClinicIdEntry';

  static Future<String?> getLastClinicForEntry() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_entryLastKey);
  }

  static Future<void> setLastClinicForEntry(String clinicId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_entryLastKey, clinicId.trim());
  }
}
