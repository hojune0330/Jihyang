import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'tabata_engine.dart';

/// 화면이 꺼져 있거나 앱이 백그라운드/종료 상태여도 구간 전환을 알려주는 로컬 알림.
///
/// Dart 타이머는 화면이 꺼지면 실행이 멈출 수 있으므로,
/// 각 구간이 바뀌는 시각을 시스템에 미리 예약해 두는 방식으로 동작한다.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _available = false;
  int _id = 1;

  static const String _channelId = 'tabata_phase_v1';
  static const String _channelName = '타바타 구간 알림';

  Future<void> init() async {
    if (kIsWeb) return; // 웹은 미지원
    try {
      tzdata.initializeTimeZones();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const init = InitializationSettings(android: androidInit);
      await _plugin.initialize(init);

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: '운동/휴식 구간 시작과 완료를 알려줍니다',
          importance: Importance.high,
        ),
      );
      await android?.requestNotificationsPermission();
      _available = true;
    } catch (e) {
      if (kDebugMode) debugPrint('notification init failed: $e');
      _available = false;
    }
  }

  /// 남은 모든 구간의 전환 시각을 예약한다.
  Future<void> scheduleSession(TabataEngine engine) async {
    if (!_available) return;
    await cancelAll();
    try {
      final phases = engine.phases;
      if (phases.isEmpty) return;

      final now = DateTime.now();
      // 현재 구간이 끝나는 시점 = 지금 + 남은 시간
      var boundary = now.add(Duration(milliseconds: engine.remainingMs));

      for (
        var i = engine.index;
        i < phases.length && i < engine.index + 150;
        i++
      ) {
        final nextIndex = i + 1;

        if (nextIndex < phases.length) {
          final next = phases[nextIndex];
          final isWork = next.type.name == 'work';
          final body = isWork
              ? '${next.setIndex}세트 · ${next.exerciseIndex} / ${next.totalExercises}개'
              : '${_fmtDuration(next.duration)} 휴식';
          await _schedule(at: boundary, title: '${next.title} 시작', body: body);
        } else {
          await _schedule(
            at: boundary,
            title: '운동 완료',
            body: '모든 라운드를 마쳤습니다. 수고하셨습니다.',
          );
        }

        // 다음 경계 = 이전 경계 + 다음 구간 길이
        if (nextIndex < phases.length) {
          boundary = boundary.add(
            Duration(seconds: phases[nextIndex].duration),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('schedule failed: $e');
    }
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return '$m분 $s초';
    if (m > 0) return '$m분';
    return '$s초';
  }

  Future<void> _schedule({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (!at.isAfter(DateTime.now())) return;
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '운동/휴식 구간 시작과 완료를 알려줍니다',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      color: Color(0xFFFF1744),
    );

    try {
      await _plugin.zonedSchedule(
        _id++,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('single schedule failed: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!_available) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      if (kDebugMode) debugPrint('cancel failed: $e');
    }
  }
}
