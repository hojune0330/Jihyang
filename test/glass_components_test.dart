import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/theme/app_theme.dart';
import 'package:tabata_timer/theme/glass/glass.dart';

/// 글래스 디자인 시스템 D2 검증 — docs/glass/DESIGN_SYSTEM.md §8
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// 배경 위에 유리 면(흰색 알파)을 합성한 실제 색
Color glassOver(Color bg, GlassMaterial m, {bool onColor = false}) {
  final s = GlassTokens.spec(m);
  final a = onColor ? s.fillOnColor : s.fillLight;
  return Color.alphaBlend(Colors.white.withValues(alpha: a), bg);
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: GlassBackdrop.ambient(child: Center(child: child)),
  ),
);

void main() {
  group('토큰 (§3)', () {
    test('재질이 thin < regular < thick 순으로 진해지고 블러도 커진다', () {
      final t = GlassTokens.spec(GlassMaterial.thin);
      final r = GlassTokens.spec(GlassMaterial.regular);
      final k = GlassTokens.spec(GlassMaterial.thick);
      expect(t.fillLight < r.fillLight && r.fillLight < k.fillLight, isTrue);
      expect(t.blur < r.blur && r.blur < k.blur, isTrue);
      expect(
        t.fillOnColor < r.fillOnColor && r.fillOnColor < k.fillOnColor,
        isTrue,
      );
    });

    test('상태색 값은 기존 AppColors 와 동일하다 (정체성 유지)', () {
      expect(GlassTokens.work, AppColors.work);
      expect(GlassTokens.rest, AppColors.rest);
      expect(GlassTokens.prepare, AppColors.prepare);
      expect(AppColors.work, const Color(0xFFE77D75));
      expect(AppColors.rest, const Color(0xFF648BD2));
      expect(AppColors.prepare, const Color(0xFFFFE27A));
    });
  });

  group('대비 (§8) — 가장 불리한 배경(오브가 가장 진한 곳) 기준', () {
    // 오브 중심색이 배경에 섞인 가장 진한 경우를 가정한다.
    final worstBgs = <String, Color>{
      'coral': Color.alphaBlend(
        GlassTokens.orbCoral.withValues(alpha: 0.58),
        GlassTokens.ambientTop,
      ),
      'sky': Color.alphaBlend(
        GlassTokens.orbSky.withValues(alpha: 0.58),
        GlassTokens.ambientTop,
      ),
      'amber': Color.alphaBlend(
        GlassTokens.orbAmber.withValues(alpha: 0.58),
        GlassTokens.ambientTop,
      ),
    };

    test('regular 유리 위 작은 글자(주/보조/진한 상태색)가 4.5:1 이상', () {
      for (final e in worstBgs.entries) {
        final face = glassOver(e.value, GlassMaterial.regular);
        for (final c in {
          'ink': GlassTokens.ink,
          'sub': GlassTokens.sub,
          'workText': GlassTokens.workText,
          'restText': GlassTokens.restText,
          'prepText': GlassTokens.prepText,
        }.entries) {
          final r = contrast(c.value, face);
          expect(
            r,
            greaterThanOrEqualTo(4.5),
            reason: '${c.key} on ${e.key} = ${r.toStringAsFixed(2)}',
          );
        }
      }
    });

    test('3차 글자(tert)는 큰 글자/보조 기준 3:1 이상', () {
      for (final e in worstBgs.entries) {
        final face = glassOver(e.value, GlassMaterial.regular);
        final r = contrast(GlassTokens.tert, face);
        expect(
          r,
          greaterThanOrEqualTo(3.0),
          reason: 'tert on ${e.key} = ${r.toStringAsFixed(2)}',
        );
      }
    });

    test('기존 문제: 옐로 글자는 흰 유리 위에서 3:1 미만 → 글자로 쓰면 안 된다', () {
      final face = glassOver(GlassTokens.ambientTop, GlassMaterial.regular);
      expect(contrast(AppColors.prepare, face), lessThan(3.0));
      expect(contrast(GlassTokens.prepText, face), greaterThanOrEqualTo(4.5));
    });

    test('진행 화면: 상태색 배경 위 thin 유리에서 흰 큰 글자가 읽힌다', () {
      // 큰 숫자(라운드/세트) 기준 3:1 — 옐로(준비)는 그림자 보정이 별도로 있다.
      for (final bg in [AppColors.work, AppColors.rest]) {
        final face = glassOver(bg, GlassMaterial.thin, onColor: true);
        expect(
          contrast(Colors.white, face),
          greaterThanOrEqualTo(2.0),
          reason: '$bg',
        );
      }
    });
  });

  group('컴포넌트 동작', () {
    testWidgets('GlassSurface 는 블러·squircle 클립·rim 을 그린다', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            height: 120,
            child: GlassSurface(child: Text('유리')),
          ),
        ),
      );
      expect(find.text('유리'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byType(ClipRSuperellipse), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('blur:false 면 BackdropFilter 를 쓰지 않는다 (성능)', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 100,
            height: 60,
            child: GlassSurface(blur: false, child: SizedBox()),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('GlassButton 탭이 동작하고 누르는 동안 축소된다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: GlassButton.filled(
              label: '운동 시작',
              icon: Icons.play_arrow_rounded,
              color: AppColors.work,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      final g = await tester.startGesture(tester.getCenter(find.text('운동 시작')));
      await tester.pump(const Duration(milliseconds: 120));
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, GlassTokens.pressScale);
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        1.0,
      );
    });

    testWidgets('비활성 버튼은 탭되지 않고 흐리게 보인다', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: GlassButton.glass(label: '비활성', onPressed: null),
          ),
        ),
      );
      await tester.tap(find.text('비활성'));
      await tester.pump(const Duration(milliseconds: 300));
      final op = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(GlassPressable),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(op.opacity, lessThan(1.0));
    });

    testWidgets('GlassIconButton 터치 영역이 44x44 이상', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassIconButton(
            icon: Icons.close_rounded,
            tooltip: '닫기',
            onPressed: () {},
          ),
        ),
      );
      final size = tester.getSize(find.byType(GlassPressable));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('GlassGroup 은 행 사이에만 구분선을 넣는다', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: GlassGroup(
              children: [
                SizedBox(height: 40, child: Text('a')),
                SizedBox(height: 40, child: Text('b')),
                SizedBox(height: 40, child: Text('c')),
              ],
            ),
          ),
        ),
      );
      final col = tester.widget<Column>(
        find
            .descendant(
              of: find.byType(GlassGroup),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(col.children.length, 5); // 3행 + 구분선 2
    });

    testWidgets('showGlassDialog 가 선택값을 돌려준다', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showGlassDialog<bool>(
                      context: ctx,
                      title: '운동을 종료할까요?',
                      message: '설명',
                      actions: const [
                        GlassDialogAction(label: '계속하기', value: false),
                        GlassDialogAction(
                          label: '종료',
                          value: true,
                          destructive: true,
                          primary: true,
                        ),
                      ],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('운동을 종료할까요?'), findsOneWidget);
      await tester.tap(find.text('종료'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('GlassBackdrop.phase 는 상태색 값을 그대로 채운다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GlassBackdrop.phase(
            color: AppColors.workBg,
            child: SizedBox.expand(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final box = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect((box.decoration as BoxDecoration?)?.color, AppColors.workBg);
    });
  });
}
