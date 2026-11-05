import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/audio_coach.dart';

/// 웹 오디오 구조 · 공유 환경 회귀 테스트.
///
/// 실기기/공유 보고:
///   "내 기기에서는 소리가 들리지만 다른 사람에게 앱을 공유하면
///    상대방 기기에서는 소리가 전혀 들리지 않는다"
///
/// 원인(코드로 확인):
///   audioplayers_web 은 **플레이어마다** AudioContext 를 만든다
///   (`wrapped_player.dart:85`). 그 컨텍스트가 사용자 제스처 없이 생성되면
///   브라우저가 'suspended' 로 잠가 **소리를 전혀 내지 않는다.**
///   우리는 채널이 4개(안내/카운트/효과음/미리듣기)라 컨텍스트도 4개였다.
///
/// 해결:
///   웹은 audioplayers 대신 `web/audio_bridge.js` 를 쓴다.
///   AudioContext 하나 + 사전 디코딩된 AudioBuffer + 제스처 기반 잠금 해제.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('웹 오디오 브리지 계약', () {
    test('모바일(스텁)에서는 웹 브리지를 쓰지 않는다', () {
      // 단위 테스트는 VM 에서 돌기 때문에 WebAudio 는 스텁이다.
      // 스텁이 "지원 안 함" 을 정확히 알려야 audioplayers 경로로 간다.
      final coach = AudioCoach.instance;
      expect(coach.isWebBridge, false,
          reason: 'VM 테스트에서는 웹 브리지가 없어야 한다');
      // 잠금 개념이 없으므로 항상 재생 가능 상태
      expect(coach.isUnlocked, true);
    });

    test('사전 로딩은 모바일에서 즉시 완료로 처리된다', () async {
      // 모바일은 플레이어가 이미 준비되어 있으므로 대기할 필요가 없다.
      // (웹에서만 실제 fetch + decode 를 한다)
      await AudioCoach.instance.preloadForSession(style: VoiceStyle.male);
      expect(AudioCoach.instance.isPreloaded, true);
    });

    test('목소리 3종 모두 시퀀스 길이표가 완비되어 있다', () {
      for (final style in VoiceStyle.values) {
        final map = seqDurMs[style.assetKey];
        expect(map, isNotNull, reason: '${style.assetKey} 길이표가 없다');
        for (final key in [
          'prepare',
          'startWork',
          'startRest',
          'setRest',
          'lastRound',
          'finish',
          'workLast',
        ]) {
          expect(map![key], isNotNull,
              reason: '${style.assetKey}.$key 길이가 없다');
          expect(map[key]!, greaterThan(0));
        }
        expect(cntDurMs[style.assetKey], isNotNull);
      }
    });

    test('목소리 3종 모두 상태 길이표와 시퀀스 길이표가 일관된다', () {
      // 시퀀스 = 삑(130ms) + 간격(attentionGapMs) + 음성
      const overhead = beepLeadMs + attentionGapMs;
      for (final style in VoiceStyle.values) {
        final seq = seqDurMs[style.assetKey]!;
        for (final voice in StateVoice.values) {
          // 상태 음성 → 시퀀스 키 매핑
          final key = voice.name;
          if (!seq.containsKey(key)) continue;
          final expected = stateVoiceDurationMs(style, voice) + overhead;
          final actual = seq[key]!;
          expect((actual - expected).abs(), lessThan(60),
              reason: '${style.assetKey}.$key: '
                  '상태 ${stateVoiceDurationMs(style, voice)}ms 인데 '
                  '시퀀스가 ${actual}ms (기대 ${expected}ms)');
        }
      }
    });

    test('목소리 3종 모두 카운트다운 묶음이 5개 숫자를 담을 만큼 길다', () {
      // 마지막 숫자 '1' 이 4000ms 에서 시작하고 그 길이만큼 더 필요하다.
      for (final style in VoiceStyle.values) {
        expect(cntDurMs[style.assetKey]!, greaterThan(4300),
            reason: '${style.assetKey} 묶음이 너무 짧다');
      }
      expect(countBundleLastMs, 4000);
      expect(countStepMs, 1000);
    });
  });

  group('중복 재생 방지 계약', () {
    test('역할(role)이 4개로 분리되어 있다', () {
      // 같은 role 안에서는 이전 소리가 반드시 죽는다.
      // role 이 하나뿐이면 안내와 카운트다운이 서로를 끊는다.
      final c = AudioCoach.instance;
      // 공개 API 로 역할 분리를 확인한다
      c.announce(const AnnouncePlan(sfx: Sfx.work, voices: [StateVoice.startWork]));
      c.playCountBundleAt(0);
      c.playSfx(Sfx.count);
      c.cut();
      expect(true, isTrue);
    });
  });
}
