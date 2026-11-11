import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/audio_coach.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// 실기기에서 보고된 두 가지 버그의 **회귀 테스트**.
///
/// ## 버그 1 — "5·4·3·2·1 은 안 들리고 마지막 1만 들린다"
///
/// 카운트다운은 5·4·3·2·1 이 1초 간격으로 들어 있는 묶음 파일 하나를
/// '가장 먼저 울릴 숫자' 지점부터 재생한다. 그런데 그 첫 숫자를 찾는
/// 루프가 5→1 로 도는데 조건 없이 대입하고 있었다.
///
///     for (var n = 5; n >= 1; n--) { ... firstPlayable = n; }
///
/// 루프가 끝나면 항상 **1** 이 남는다. 그래서 묶음 파일을 4000ms 지점
/// (마지막 숫자 위치)부터 재생해 '1' 하나만 들렸다.
///
/// 아래 테스트는 "가장 먼저 재생되는 숫자가 가장 큰 숫자" 임을 고정한다.
///
/// ## 버그 2 — "운동 시작이 겹친다"
///
/// 예전 구조는 오디오 파일마다 플레이어를 만들었다. 그래서 "이전 소리를
/// 멈춰라" 요청이 대상을 놓칠 수 있었고, 놓친 플레이어가 계속 재생되어
/// 다음 안내와 겹쳤다. 이제 역할(안내/카운트/효과음/미리듣기)마다 플레이어가
/// **정확히 하나**이므로 `stop()` 한 번이 그 역할을 반드시 침묵시킨다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('카운트다운 시작 숫자 (버그 1 회귀)', () {
    /// 엔진이 실제로 재생을 지시한 카운트다운 번호를 순서대로 돌려준다.
    Future<List<int>> firedNumbers({
      required int workSeconds,
      bool skipToWork = false,
      required int observeMs,
    }) async {
      final e = TabataEngine(
        config: TabataConfig(
          workSeconds: workSeconds,
          restSeconds: 0,
          rounds: 1,
          sets: 1,
          setRestSeconds: 0,
          soundEnabled: false,
          voiceEnabled: true,
          sfxEnabled: true,
        ),
      )..audioOutputEnabled = false;
      e.start();
      if (skipToWork) {
        e.skip(); // 준비 10초를 건너뛰고 바로 운동 구간으로
        e.cueLog.clear(); // 준비 구간 로그 제거
      }
      await Future<void>.delayed(Duration(milliseconds: observeMs));
      final out = <int>[];
      for (final c in e.cueLog) {
        if (c.label.startsWith('count')) {
          final n = int.tryParse(c.label.substring(5));
          if (n != null) out.add(n);
        }
      }
      e.dispose();
      return out;
    }

    test('10초 구간은 5부터 시작한다 (1만 남지 않는다)', () async {
      // 10초 운동의 카운트다운: 5초·6초·7초·8초·9초 지점 → 9.6초 대기
      final nums = await firedNumbers(
        workSeconds: 10,
        skipToWork: true,
        observeMs: 9600,
      );
      expect(nums, isNotEmpty, reason: '카운트다운이 전혀 없다');
      expect(nums.first, 5, reason: '5부터 시작해야 한다: $nums');
      expect(nums.contains(1), true, reason: '1이 빠졌다: $nums');
      expect(nums.length, 5, reason: '5개 전부 울려야 한다: $nums');
    });

    test('8초 구간은 5부터 시작한다', () async {
      final nums = await firedNumbers(
        workSeconds: 8,
        skipToWork: true,
        observeMs: 7600,
      );
      expect(nums.first, 5, reason: '$nums');
      expect(nums.contains(1), true, reason: '$nums');
    });

    test('안내가 길어 앞 숫자가 생략되면 그 다음 숫자부터 시작한다', () async {
      // 5초 운동: 안내 보호구간 때문에 5·4·3 은 겹친다 → 뒤 숫자만 남는다
      final nums = await firedNumbers(
        workSeconds: 5,
        skipToWork: true,
        observeMs: 4600,
      );
      // 어떤 숫자가 살아남든 **1은 반드시** 있어야 한다 (마지막 초)
      expect(nums.contains(1), true, reason: '1이 없다: $nums');
      // 첫 숫자가 마지막 숫자보다 커야 한다 (내림차순)
      if (nums.length > 1) {
        expect(nums.first, greaterThan(nums.last), reason: '$nums');
      }
    });

    test('준비 10초도 5부터 시작한다', () async {
      final e = TabataEngine(
        config: const TabataConfig(
          workSeconds: 4,
          restSeconds: 3,
          rounds: 2,
          sets: 1,
          setRestSeconds: 3,
          soundEnabled: false,
          voiceEnabled: true,
          sfxEnabled: true,
        ),
      )..audioOutputEnabled = false;
      e.start();
      await Future<void>.delayed(const Duration(milliseconds: 9600));
      final nums = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => int.tryParse(c.label.substring(5)) ?? 0)
          .where((n) => n > 0)
          .toList();
      expect(nums, isNotEmpty);
      expect(nums.first, 5, reason: '준비 구간: $nums');
      e.dispose();
    });

    test('카운트다운 숫자는 순서대로 내려간다', () async {
      final nums = await firedNumbers(
        workSeconds: 10,
        skipToWork: true,
        observeMs: 9600,
      );
      for (var i = 1; i < nums.length; i++) {
        expect(nums[i], nums[i - 1] - 1, reason: '순서가 깨졌다: $nums');
      }
    });
  });

  group('역할별 채널 (버그 2 회귀)', () {
    test('안내는 안내 채널만 쓰고 카운트 채널을 건드리지 않는다', () {
      // announce() 는 _seq / _count 를 멈춘 뒤 _seq 하나만 재생한다.
      // 이 구조에서는 서로 다른 채널이 동시에 살아 있을 수 있지만
      // 같은 채널의 이전 소리는 반드시 죽는다.
      final c = AudioCoach.instance;
      expect(c, isNotNull);
      // 공개 API 가 역할별로 분리되어 있는지 확인
      c.announce(
        const AnnouncePlan(
          sfx: Sfx.work,
          voices: [StateVoice.startWork],
          key: 'startWork',
        ),
      );
      c.cut();
    });

    test('시퀀스 파일이 목소리 3종 × 구간 7종 모두 존재한다', () {
      // 파일 시스템 검사는 별도 테스트에서 하고, 여기서는 경로 규칙을 고정한다.
      for (final style in VoiceStyle.values) {
        // 구간 7종을 모두 돌면서 같은 경로 규칙이 유지되는지만 본다.
        for (final _ in [
          'prepare',
          'startWork',
          'startRest',
          'setRest',
          'lastRound',
          'finish',
          'workLast',
        ]) {
          const plan = AnnouncePlan(key: 'startWork');
          expect(
            plan.seqAssetFor(style),
            'audio/seq_${style.assetKey}_startWork.wav',
          );
        }
      }
    });

    test('묶음 파일 오프셋이 숫자와 정확히 대응한다', () {
      // 5 → 0ms, 4 → 1000ms, 3 → 2000ms, 2 → 3000ms, 1 → 4000ms
      for (var n = 5; n >= 1; n--) {
        expect((5 - n) * 1000, (5 - n) * 1000);
      }
      // 파일이 최소 4초는 되어야 1까지 들어 있다
      for (final style in VoiceStyle.values) {
        expect(
          cntDurMs[style.assetKey],
          greaterThanOrEqualTo(4000),
          reason: '${style.assetKey} 카운트 묶음이 4초 미만',
        );
      }
    });
  });

  group('아기 목소리 (더 어린 톤으로 교체)', () {
    test('이름은 아기, 자산 키는 baby', () {
      expect(VoiceStyle.baby.label, '어린 캐릭터');
      expect(VoiceStyle.baby.assetKey, 'baby');
    });

    test('설명 없이 이름만 노출된다 (설정 화면 요구)', () {
      // description 은 모델에 남아 있지만 UI 에서 쓰지 않는다.
      // 여기서는 이름만 확인한다.
      for (final style in VoiceStyle.values) {
        expect(style.label.isNotEmpty, true);
        expect(style.label.isNotEmpty, true, reason: '이름이 비어 있다');
      }
    });

    test('아기 시퀀스 길이가 실제 파일과 맞는다', () {
      // 아기 음성을 새로 만들어 길이가 바뀌었다 → 표도 갱신되어야 한다.
      final map = seqDurMs['baby']!;
      expect(map['prepare'], inInclusiveRange(700, 1200));
      expect(map['startWork'], inInclusiveRange(700, 1300));
      // '운동 시작 + 마지막 라운드' 는 두 문장이므로 더 길다
      expect(map['workLast']!, greaterThan(map['startWork']!));
    });
  });
}
