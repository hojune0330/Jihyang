import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 타이머 진행 상태 스냅샷 저장소.
///
/// 화면이 꺼지거나 앱이 백그라운드로 밀려 프로세스가 종료되어도
/// 마지막 진행 지점을 복원해 시간이 어긋나지 않게 한다.
class SessionStore {
  static const String _key = 'tabata_session_v1';

  static Future<void> save(Map<String, dynamic> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(snapshot));
    } catch (e) {
      if (kDebugMode) debugPrint('session save failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('session load failed: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      if (kDebugMode) debugPrint('session clear failed: $e');
    }
  }
}
