import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/screens/settings_screen.dart';
import 'package:tabata_timer/services/preset_store.dart';
import 'package:tabata_timer/theme/app_theme.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> loadPretendard() async {
    final loader = FontLoader('Pretendard');
    for (final f in const [
      'assets/fonts/Pretendard-Regular.otf',
      'assets/fonts/Pretendard-SemiBold.otf',
      'assets/fonts/Pretendard-Bold.otf',
      'assets/fonts/Pretendard-ExtraBold.otf',
    ]) {
      loader.addFont(
        File(f).readAsBytes().then(
          (b) => ByteData.view(Uint8List.fromList(b).buffer),
        ),
      );
    }
    await loader.load();
  }

  testWidgets('캡처: 설정 화면 저장한 운동 구성 섹션', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() async {
      await PresetStore.add(
        '아침 타바타',
        const TabataConfig(workSeconds: 30, restSeconds: 15, rounds: 8),
      );
      await PresetStore.add(
        '점심 짧게',
        const TabataConfig(workSeconds: 20, restSeconds: 10, rounds: 6),
      );
    });

    await tester.runAsync(loadPretendard);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: RepaintBoundary(
          key: key,
          child: const SettingsScreen(initial: TabataConfig()),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('저장한 운동 구성'), findsOneWidget);
    expect(find.text('아침 타바타'), findsWidgets);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      File(
        '/tmp/shot_settings_presets.png',
      ).writeAsBytesSync(bytes.buffer.asUint8List());
    });
  });
}
