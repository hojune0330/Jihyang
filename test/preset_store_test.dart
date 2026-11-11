import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/preset_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('구성 여러 개를 저장하고 다시 불러온다', () async {
    final a = await PresetStore.add(
      '아침',
      const TabataConfig(
        workSeconds: 40,
        restSeconds: 20,
        rounds: 6,
        sets: 2,
        setRestSeconds: 90,
      ),
    );
    final b = await PresetStore.add(
      '저녁',
      const TabataConfig(
        workSeconds: 20,
        restSeconds: 10,
        rounds: 10,
        sets: 1,
        setRestSeconds: 0,
      ),
    );
    expect(a, isNotNull);
    expect(b, isNotNull);

    final list = await PresetStore.load();
    expect(list.map((p) => p.name), ['아침', '저녁']);
    expect(list[0].config.workSeconds, 40);
    expect(list[0].config.sets, 2);
    expect(list[0].config.setRestSeconds, 90);
    expect(list[1].config.rounds, 10);
  });

  test('빈 이름은 자동 이름으로 저장된다', () async {
    final p = await PresetStore.add('  ', const TabataConfig());
    expect(p!.name, '구성 1');
  });

  test('구성 수정과 삭제가 반영된다', () async {
    final p = await PresetStore.add('원래', const TabataConfig());
    await PresetStore.update(
      p!.copyWith(name: '바뀜', config: const TabataConfig(rounds: 3)),
    );
    var list = await PresetStore.load();
    expect(list.single.name, '바뀜');
    expect(list.single.config.rounds, 3);

    await PresetStore.remove(p.id);
    list = await PresetStore.load();
    expect(list, isEmpty);
  });

  test('최대 개수를 넘기면 추가되지 않는다', () async {
    for (var i = 0; i < PresetStore.maxPresets; i++) {
      await PresetStore.add('n$i', const TabataConfig());
    }
    final extra = await PresetStore.add('넘침', const TabataConfig());
    expect(extra, isNull);
    expect((await PresetStore.load()).length, PresetStore.maxPresets);
  });
}
