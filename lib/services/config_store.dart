import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tabata_config.dart';

/// 설정값 영구 저장
class ConfigStore {
  static const String _key = 'tabata_config_v1';

  static Future<TabataConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const TabataConfig();
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) return TabataConfig.fromJson(map);
      if (map is Map) {
        return TabataConfig.fromJson(Map<String, dynamic>.from(map));
      }
      return const TabataConfig();
    } catch (e) {
      if (kDebugMode) debugPrint('config load failed: $e');
      return const TabataConfig();
    }
  }

  static Future<void> save(TabataConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(config.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('config save failed: $e');
    }
  }
}
