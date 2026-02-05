import 'package:shared_preferences/shared_preferences.dart';

class LastClinicStore {
  static String _key(String uid) => 'lastClinicId:$uid';

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
}
