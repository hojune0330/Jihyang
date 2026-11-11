import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/screens/settings_screen.dart';

/// 설정 화면의 목소리 목록에 **설명 문구가 없고 이름만** 있는지 검증한다.
///
/// 요구사항: "목소리 종류에서 설명은 지워줘"
///
/// 주의: 설정 화면은 세로로 긴 ListView 라서 기본 테스트 뷰포트(800x600)
/// 에서는 목소리 타일이 화면 밖에 있다. 위젯 트리에는 존재하지만
/// `find.text` 는 오프스테이지(캐시되지 않은) 항목을 잡지 못하므로
/// 테스트 뷰포트를 실제 폰 세로 화면만큼 키워서 확인한다.
void main() {
  /// 세로로 긴 폰 화면(390x844)을 흉내 낸다.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // 390x844 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen(initial: TabataConfig())),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('목소리 타일에는 이름만 있고 설명은 표시되지 않는다', (tester) async {
    await pumpSettings(tester);

    // 목소리 목록까지 스크롤해서 확실히 화면 안에 올린다.
    await tester.scrollUntilVisible(
      find.text('어린 캐릭터'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 이름 3종이 보인다
    expect(find.text('스포츠 MC'), findsOneWidget);
    expect(find.text('화난 코치'), findsOneWidget);
    expect(find.text('어린 캐릭터'), findsOneWidget);

    // 모델에 남아 있는 설명 문구는 화면에 나타나지 않아야 한다
    for (final style in VoiceStyle.values) {
      expect(
        find.text(style.description),
        findsNothing,
        reason: '설명이 아직 표시된다: ${style.description}',
      );
    }
  });

  testWidgets('아기 목소리를 선택할 수 있다', (tester) async {
    await pumpSettings(tester);

    await tester.scrollUntilVisible(
      find.text('어린 캐릭터'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('어린 캐릭터'));
    // 탭하면 미리 듣기가 함께 실행된다. _Channel.play 는
    // stop → setVolume → setSource → seek → resume 를 **순차로** await 하고
    // 각 단계마다 2500ms 타임아웃 타이머를 건다. 오디오 플러그인이 없는
    // 테스트 환경에서는 이 단계들이 끝나지 않으므로, 가짜 시계를
    // 충분히(단계 수 × 타임아웃 이상) 진행시켜 타이머를 모두 소진시킨다.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 3));
    }

    // 탭 후에도 화면이 정상 (예외 없음)
    expect(find.text('어린 캐릭터'), findsOneWidget);
  });
}
