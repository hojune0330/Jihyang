import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workout_record.dart';

/// 운동 기록 영구 저장소 (shared_preferences, JSON 배열)
class WorkoutStore {
  static const String _key = 'tabata_workout_records_v1';

  /// 너무 커지지 않도록 최근 500건만 보관
  static const int maxRecords = 500;

  static List<WorkoutRecord> _cache = const <WorkoutRecord>[];
  static bool _loaded = false;

  static List<WorkoutRecord> get cached => List.unmodifiable(_cache);

  static Future<List<WorkoutRecord>> load({bool force = false}) async {
    if (_loaded && !force) return List.unmodifiable(_cache);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        _cache = const <WorkoutRecord>[];
        _loaded = true;
        return const <WorkoutRecord>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _cache = const <WorkoutRecord>[];
        _loaded = true;
        return const <WorkoutRecord>[];
      }
      final list = <WorkoutRecord>[];
      for (final e in decoded) {
        if (e is Map) {
          try {
            list.add(WorkoutRecord.fromJson(Map<String, dynamic>.from(e)));
          } catch (err) {
            if (kDebugMode) debugPrint('record decode failed: $err');
          }
        }
      }
      // 최신순
      list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      _cache = list;
      _loaded = true;
      return List.unmodifiable(_cache);
    } catch (e) {
      if (kDebugMode) debugPrint('workout load failed: $e');
      _cache = const <WorkoutRecord>[];
      _loaded = true;
      return const <WorkoutRecord>[];
    }
  }

  /// 기록 추가. 같은 id 가 이미 있으면 무시(중복 저장 방지).
  static Future<bool> add(WorkoutRecord record) async {
    await load();
    if (_cache.any((r) => r.id == record.id)) return false;
    final next = <WorkoutRecord>[record, ..._cache];
    if (next.length > maxRecords) {
      next.removeRange(maxRecords, next.length);
    }
    _cache = next;
    await _persist();
    return true;
  }

  static Future<void> remove(int id) async {
    await load();
    _cache = _cache.where((r) => r.id != id).toList();
    await _persist();
  }

  static Future<void> clear() async {
    _cache = const <WorkoutRecord>[];
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_cache.map((r) => r.toJson()).toList());
      await prefs.setString(_key, raw);
    } catch (e) {
      if (kDebugMode) debugPrint('workout save failed: $e');
    }
  }

  // ------------------------------------------------------------ 집계

  /// 오늘 기록
  static List<WorkoutRecord> today(List<WorkoutRecord> all) =>
      all.where((r) => r.isToday).toList();

  /// 이번 주 기록
  static List<WorkoutRecord> thisWeek(List<WorkoutRecord> all) =>
      all.where((r) => r.isThisWeek).toList();

  /// 누적 운동 횟수 (완료 + 중도 종료 전부)
  static int totalCount(List<WorkoutRecord> all) => all.length;

  /// 완료한 운동 횟수
  static int completedCount(List<WorkoutRecord> all) =>
      all.where((r) => r.isCompleted).length;

  /// 누적 운동 시간(초) — 실제로 타이머가 흐른 시간 합
  static int totalActiveSeconds(List<WorkoutRecord> all) =>
      all.fold<int>(0, (a, r) => a + r.activeSeconds);

  /// 날짜별 그룹 (최신 날짜 먼저)
  static List<MapEntry<String, List<WorkoutRecord>>> groupByDate(
    List<WorkoutRecord> all,
  ) {
    final map = <String, List<WorkoutRecord>>{};
    for (final r in all) {
      map.putIfAbsent(r.dateKey, () => <WorkoutRecord>[]).add(r);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) MapEntry(k, map[k]!)];
  }
}
