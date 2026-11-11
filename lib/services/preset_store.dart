import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tabata_config.dart';

/// 사용자가 직접 만든 운동 구성 1건 (이름 + 구성값)
class WorkoutPreset {
  const WorkoutPreset({
    required this.id,
    required this.name,
    required this.config,
  });

  final int id;
  final String name;
  final TabataConfig config;

  WorkoutPreset copyWith({String? name, TabataConfig? config}) => WorkoutPreset(
    id: id,
    name: name ?? this.name,
    config: config ?? this.config,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'config': config.toJson(),
  };

  factory WorkoutPreset.fromJson(Map<String, dynamic> json) {
    final cfg = json['config'];
    return WorkoutPreset(
      id:
          (json['id'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : '이름 없는 구성',
      config: cfg is Map
          ? TabataConfig.fromJson(Map<String, dynamic>.from(cfg))
          : const TabataConfig(),
    );
  }
}

/// 운동 구성 목록 영구 저장 (shared_preferences, JSON 배열).
/// 현재 설정(ConfigStore)과는 별도로, 이름 붙인 구성을 여러 개 보관한다.
class PresetStore {
  static const String _key = 'tabata_presets_v1';

  /// 너무 많아지지 않도록 최대 개수
  static const int maxPresets = 30;

  static Future<List<WorkoutPreset>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const <WorkoutPreset>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <WorkoutPreset>[];
      final list = <WorkoutPreset>[];
      for (final e in decoded) {
        if (e is Map) {
          try {
            list.add(WorkoutPreset.fromJson(Map<String, dynamic>.from(e)));
          } catch (err) {
            if (kDebugMode) debugPrint('preset decode failed: $err');
          }
        }
      }
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('preset load failed: $e');
      return const <WorkoutPreset>[];
    }
  }

  static Future<void> _save(List<WorkoutPreset> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(list.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('preset save failed: $e');
    }
  }

  /// 새 구성 추가. 목록 끝에 붙이고 추가된 항목을 돌려준다.
  static Future<WorkoutPreset?> add(String name, TabataConfig config) async {
    final list = await load();
    if (list.length >= maxPresets) return null;
    final preset = WorkoutPreset(
      id: DateTime.now().millisecondsSinceEpoch,
      name: name.trim().isEmpty ? '구성 ${list.length + 1}' : name.trim(),
      config: config,
    );
    await _save([...list, preset]);
    return preset;
  }

  /// 기존 구성 덮어쓰기 (이름·설정)
  static Future<void> update(WorkoutPreset preset) async {
    final list = await load();
    await _save([for (final p in list) p.id == preset.id ? preset : p]);
  }

  static Future<void> remove(int id) async {
    final list = await load();
    await _save(list.where((p) => p.id != id).toList());
  }
}
