// lib/utils/tour_helper.dart
//
// 인앱 가이드 투어 완료 여부 관리 (SharedPreferences)

import 'package:shared_preferences/shared_preferences.dart';

class TourHelper {
  static const _prefix = 'tour_completed_';

  static Future<bool> isCompleted(String screenKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$screenKey') ?? false;
  }

  static Future<void> markCompleted(String screenKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$screenKey', true);
  }

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  // ── 화면 키 상수 ─────────────────────────────────────────────
  static const userHome   = 'user_home';
  static const adminHome  = 'admin_home';
}
