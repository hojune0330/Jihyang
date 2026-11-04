/// 시간 표기 유틸 (앱 전체 공통)
library;

/// 00:30 / 1:02:30
String fmtClock(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 24분 30초 / 1시간 02분
String fmtKorean(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h시간 ${m.toString().padLeft(2, '0')}분';
  if (m > 0) return '$m분 ${s.toString().padLeft(2, '0')}초';
  return '$s초';
}

/// 1분 / 30초 / 없음
String fmtKoreanShort(int seconds) {
  if (seconds <= 0) return '없음';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m > 0 && s > 0) return '$m분 $s초';
  if (m > 0) return '$m분';
  return '$s초';
}

/// 누적 시간용 (예: 12시간 40분 / 40분 / 0분)
String fmtAccumulated(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h > 0) return '$h시간 $m분';
  return '$m분';
}
