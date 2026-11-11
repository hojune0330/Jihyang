import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../services/audio_coach.dart';
import '../services/preset_store.dart';
import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';
import '../utils/fmt.dart';
import '../widgets/wheel_picker.dart';

/// 별도 화면 — 운동 설정
///
/// 아이폰 알람 스타일 휠 피커로 운동/휴식/세트 간 휴식/라운드/세트를 설정하고,
/// 사운드(효과음·음성·목소리·볼륨·미리 듣기)를 개별 조절한다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.initial});

  final TabataConfig initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TabataConfig _c;
  List<WorkoutPreset> _presets = const <WorkoutPreset>[];

  @override
  void initState() {
    super.initState();
    _c = widget.initial;
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final list = await PresetStore.load();
    if (!mounted) return;
    setState(() => _presets = list);
  }

  /// 현재 운동 구성을 이름 붙여 저장
  Future<void> _savePreset() async {
    final ctrl = TextEditingController();
    final name = await showGlassDialog<bool>(
      context: context,
      title: '운동 구성 이름',
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 12,
        style: GlassTokens.body,
        decoration: InputDecoration(
          hintText: '예: 아침 타바타',
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassTokens.rSm),
            borderSide: BorderSide.none,
          ),
        ),
        // 엔터 = 저장. 다이얼로그(최상단 라우트)만 닫는다.
        onSubmitted: (_) => Navigator.of(context).pop(true),
      ),
      actions: const [
        GlassDialogAction(label: '취소', value: false),
        GlassDialogAction(label: '저장', value: true, primary: true),
      ],
    );
    final typed = name == true ? ctrl.text : null;
    ctrl.dispose();
    if (typed == null) return;
    final added = await PresetStore.add(typed, _workoutOnly(_c));
    if (!mounted) return;
    if (added == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('구성은 최대 30개까지 저장할 수 있어요.')));
      return;
    }
    await _loadPresets();
  }

  /// 운동 구성 5개 필드만 골라낸 설정 (사운드 설정은 구성에 포함하지 않음)
  static TabataConfig _workoutOnly(TabataConfig c) => TabataConfig(
    workSeconds: c.workSeconds,
    restSeconds: c.restSeconds,
    rounds: c.rounds,
    sets: c.sets,
    setRestSeconds: c.setRestSeconds,
  );

  /// 저장된 구성의 운동 5개 필드만 편집 중인 설정에 불러온다 (저장 버튼을 눌러야 메인에 반영)
  void _applyPreset(WorkoutPreset p) {
    final w = p.config;
    _update(
      _c.copyWith(
        workSeconds: w.workSeconds,
        restSeconds: w.restSeconds,
        rounds: w.rounds,
        sets: w.sets,
        setRestSeconds: w.setRestSeconds,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${p.name}" 구성을 불러왔어요. 저장을 눌러 적용하세요.')),
    );
  }

  Future<void> _deletePreset(WorkoutPreset p) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      title: '"${p.name}" 삭제',
      message: '저장된 운동 구성을 삭제할까요?',
      actions: const [
        GlassDialogAction(label: '취소', value: false),
        GlassDialogAction(
          label: '삭제',
          value: true,
          destructive: true,
          primary: true,
        ),
      ],
    );
    if (ok != true) return;
    await PresetStore.remove(p.id);
    await _loadPresets();
  }

  void _update(TabataConfig next) {
    final styleChanged = _c.voiceStyle != next.voiceStyle;
    setState(() => _c = next);
    // 설정 즉시 반영 (미리 듣기 볼륨/목소리)
    AudioCoach.instance.applyConfig(next);
    // 목소리가 바뀌면 새 목소리 파일을 미리 받아 둔다.
    // (안 받아 두면 첫 안내가 늦게 나오거나 웹에서 무음이 된다)
    if (styleChanged) {
      AudioCoach.instance.preloadForSession(style: next.voiceStyle);
    }
  }

  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlassTokens.ambientTop,
      extendBodyBehindAppBar: true,
      appBar: GlassNavBar(
        title: '운동 설정',
        scrolled: _scrolled,
        trailing: GlassPressable(
          onTap: () => Navigator.of(context).pop(_c),
          semanticLabel: '저장',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(
              '저장',
              style: GlassTokens.title.copyWith(color: GlassTokens.tintText),
            ),
          ),
        ),
      ),
      body: GlassBackdrop.ambient(
        preset: BackdropPreset.settings,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            final v = n.metrics.pixels > 4;
            if (v != _scrolled) setState(() => _scrolled = v);
            return false;
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              GlassTokens.screenX,
              MediaQuery.paddingOf(context).top + 72,
              GlassTokens.screenX,
              36 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              const GlassSectionLabel('운동 구성'),
              GlassGroup(
                children: [
                  _wheelRow(
                    label: '운동 시간',
                    value: fmtClock(_c.workSeconds),
                    accent: AppColors.work,
                    valueColor: GlassTokens.ink,
                    onTap: () => _openDuration(
                      title: '운동 시간',
                      subtitle: '한 라운드 동안 운동하는 시간입니다.',
                      seconds: _c.workSeconds,
                      accent: AppColors.work,
                      minSeconds: 5,
                      apply: (v) => _update(_c.copyWith(workSeconds: v)),
                    ),
                  ),
                  _wheelRow(
                    label: '휴식 시간',
                    value: fmtClock(_c.restSeconds),
                    accent: AppColors.rest,
                    valueColor: GlassTokens.ink,
                    onTap: () => _openDuration(
                      title: '휴식 시간',
                      subtitle: '라운드 사이에 쉬는 시간입니다. 0초면 휴식 없이 진행합니다.',
                      seconds: _c.restSeconds,
                      accent: AppColors.rest,
                      minSeconds: 0,
                      apply: (v) => _update(_c.copyWith(restSeconds: v)),
                    ),
                  ),
                  _wheelRow(
                    label: '라운드',
                    value: '${_c.rounds}회',
                    accent: AppColors.prepare,
                    valueColor: GlassTokens.ink,
                    onTap: () => _openCount(
                      title: '라운드',
                      subtitle: '한 세트 안에서 운동을 반복하는 횟수입니다.',
                      value: _c.rounds,
                      min: 1,
                      max: 99,
                      suffix: '회',
                      accent: AppColors.prepare,
                      apply: (v) => _update(_c.copyWith(rounds: v)),
                    ),
                  ),
                  _wheelRow(
                    label: '세트',
                    value: '${_c.sets}세트',
                    accent: AppColors.textPrimary,
                    valueColor: GlassTokens.ink,
                    onTap: () => _openCount(
                      title: '세트',
                      subtitle: '라운드 묶음을 몇 번 반복할지 정합니다.',
                      value: _c.sets,
                      min: 1,
                      max: 20,
                      suffix: '세트',
                      accent: AppColors.textPrimary,
                      apply: (v) => _update(_c.copyWith(sets: v)),
                    ),
                  ),
                  if (_c.sets > 1)
                    _wheelRow(
                      label: '세트 간 휴식',
                      value: fmtClock(_c.setRestSeconds),
                      accent: AppColors.rest,
                      valueColor: GlassTokens.ink,
                      onTap: () => _openDuration(
                        title: '세트 간 휴식',
                        subtitle: '세트가 바뀔 때 쉬는 시간입니다. 마지막 세트 뒤에는 적용되지 않습니다.',
                        seconds: _c.setRestSeconds,
                        accent: AppColors.rest,
                        minSeconds: 0,
                        apply: (v) => _update(_c.copyWith(setRestSeconds: v)),
                      ),
                    ),
                ],
              ),
              if (_c.sets <= 1)
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Text(
                    '세트가 1개면 세트 간 휴식은 사용되지 않습니다.',
                    style: GlassTokens.caption,
                  ),
                ),
              const SizedBox(height: GlassTokens.s3),
              _summaryCard(),

              const SizedBox(height: 26),
              const GlassSectionLabel('저장한 운동 구성'),
              _presetSection(),

              const SizedBox(height: 26),
              const GlassSectionLabel('사운드'),
              GlassGroup(
                children: [
                  _switchRow(
                    label: '전체 사운드',
                    subtitle: '끄면 음성·효과음이 모두 나오지 않습니다',
                    value: _c.soundEnabled,
                    accent: AppColors.textPrimary,
                    onChanged: (v) => _update(_c.copyWith(soundEnabled: v)),
                  ),
                  _switchRow(
                    label: '효과음',
                    subtitle: '운동 시작 · 휴식 시작 · 세트 전환 · 완료 알림',
                    value: _c.sfxEnabled,
                    accent: AppColors.work,
                    enabled: _c.soundEnabled,
                    onChanged: (v) => _update(_c.copyWith(sfxEnabled: v)),
                  ),
                  _volumeRow(
                    label: '효과음 볼륨',
                    value: _c.sfxVolume,
                    accent: AppColors.work,
                    valueColor: GlassTokens.ink,
                    enabled: _c.soundEnabled && _c.sfxEnabled,
                    onChanged: (v) => _update(_c.copyWith(sfxVolume: v)),
                    onPreview: () => AudioCoach.instance.previewSfx(Sfx.work),
                  ),
                  _switchRow(
                    label: '음성 안내',
                    subtitle: '준비·운동·휴식 안내와 마지막 5초 카운트다운을 읽어 줍니다',
                    value: _c.voiceEnabled,
                    accent: AppColors.prepare,
                    enabled: _c.soundEnabled,
                    onChanged: (v) => _update(_c.copyWith(voiceEnabled: v)),
                  ),
                  _volumeRow(
                    label: '음성 볼륨',
                    value: _c.voiceVolume,
                    accent: AppColors.prepare,
                    valueColor: GlassTokens.ink,
                    enabled: _c.soundEnabled && _c.voiceEnabled,
                    onChanged: (v) => _update(_c.copyWith(voiceVolume: v)),
                    onPreview: () =>
                        AudioCoach.instance.previewVoice(_c.voiceStyle),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              _voiceStyleSection(),
              if (!_c.soundEnabled) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    SizedBox(width: 6),
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: GlassTokens.tert,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '전체 사운드가 꺼져 있어 음성·효과음 설정이 적용되지 않습니다.',
                        style: GlassTokens.caption,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Center(
                child: Text(
                  '준비 시간 ${TabataConfig.prepareSeconds}초는 항상 포함됩니다.',
                  style: GlassTokens.caption.copyWith(color: GlassTokens.tert),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 휠 피커

  Future<void> _openDuration({
    required String title,
    required String subtitle,
    required int seconds,
    required Color accent,
    required int minSeconds,
    required ValueChanged<int> apply,
  }) async {
    // 시트 내부에서만 쓰는 임시 값 (드래그할 때마다 즉시 반영)
    var current = seconds;
    final maxMinutes = (3600 ~/ 60);

    await showWheelSheet(
      context: context,
      title: title,
      subtitle: subtitle,
      accent: accent,
      onDone: () {},
      picker: StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          children: [
            WheelDurationPicker(
              seconds: current,
              accent: accent,
              maxMinutes: maxMinutes,
              onChanged: (v) {
                final clamped = v < minSeconds ? minSeconds : v;
                setSheetState(() => current = clamped);
                apply(clamped);
              },
            ),
            const SizedBox(height: 6),
            Text(
              fmtKorean(current),
              style: TextStyle(
                color: GlassTokens.sub,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCount({
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required String suffix,
    required Color accent,
    required ValueChanged<int> apply,
  }) async {
    var current = value;

    await showWheelSheet(
      context: context,
      title: title,
      subtitle: subtitle,
      accent: accent,
      onDone: () {},
      picker: StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          children: [
            WheelColumn(
              value: current,
              min: min,
              max: max,
              accent: accent,
              suffix: suffix,
              width: 140,
              itemExtent: 48,
              visibleRows: 5,
              onChanged: (v) {
                setSheetState(() => current = v);
                apply(v);
              },
            ),
            const SizedBox(height: 6),
            Text(
              '$current$suffix',
              style: TextStyle(
                color: GlassTokens.sub,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 행 위젯

  Widget _wheelRow({
    required String label,
    required String value,
    required Color accent,
    required Color valueColor,
    required VoidCallback onTap,
  }) {
    return GlassPressable(
      onTap: onTap,
      scale: 0.985,
      semanticLabel: label,
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
          child: Row(
            children: [
              Text(label, style: GlassTokens.body),
              const Spacer(),
              Text(
                value,
                style: GlassTokens.number(
                  19,
                  color: valueColor,
                ).copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: GlassTokens.tert,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required String subtitle,
    required bool value,
    required Color accent,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final dim = !enabled;
    return GlassPressable(
      onTap: enabled ? () => onChanged(!value) : null,
      scale: 0.985,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GlassTokens.body.copyWith(
                      color: dim ? GlassTokens.tert : GlassTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GlassTokens.caption.copyWith(
                      color: dim
                          ? GlassTokens.tert.withValues(alpha: 0.7)
                          : GlassTokens.sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _GlassSwitch(
              value: value,
              accent: GlassTokens.tint,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _volumeRow({
    required String label,
    required double value,
    required Color accent,
    required Color valueColor,
    required bool enabled,
    required ValueChanged<double> onChanged,
    required VoidCallback onPreview,
  }) {
    final dim = !enabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: GlassTokens.body.copyWith(
                  color: dim ? GlassTokens.tert : GlassTokens.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  color: dim ? GlassTokens.tert : GlassTokens.sub,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: GlassTokens.tabular,
                ),
              ),
              const SizedBox(width: 8),
              GlassPressable(
                onTap: dim ? null : onPreview,
                semanticLabel: '미리 듣기',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Text(
                    '미리 듣기',
                    style: GlassTokens.label.copyWith(
                      color: GlassTokens.tintText,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              activeTrackColor: dim
                  ? GlassTokens.tert.withValues(alpha: 0.4)
                  : GlassTokens.tint,
              inactiveTrackColor: GlassTokens.ink.withValues(alpha: 0.08),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 11,
                elevation: 3,
                pressedElevation: 5,
              ),
              overlayShape: SliderComponentShape.noOverlay,
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              divisions: 10,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceStyleSection() {
    final enabled = _c.soundEnabled && _c.voiceEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlassSectionLabel('목소리 종류'),
        GlassGroup(
          children: [
            for (final style in VoiceStyle.values) _voiceTile(style, enabled),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('각 목소리를 눌러 미리 들어볼 수 있습니다.', style: GlassTokens.caption),
        ),
      ],
    );
  }

  Widget _voiceTile(VoiceStyle style, bool enabled) {
    final selected = _c.voiceStyle == style;
    return GlassPressable(
      onTap: enabled
          ? () {
              _update(_c.copyWith(voiceStyle: style));
              AudioCoach.instance.previewVoice(style);
            }
          : null,
      scale: 0.985,
      semanticLabel: style.label,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  style.label,
                  style: GlassTokens.body.copyWith(
                    color: enabled ? GlassTokens.ink : GlassTokens.tert,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: GlassTokens.state,
                opacity: selected ? 1 : 0,
                child: const Icon(
                  Icons.check_rounded,
                  size: 22,
                  color: GlassTokens.tintText,
                ),
              ),
              IconButton(
                onPressed: enabled
                    ? () => AudioCoach.instance.previewVoice(style)
                    : null,
                iconSize: 20,
                tooltip: '미리 듣기',
                icon: Icon(
                  Icons.play_circle_outline_rounded,
                  color: enabled ? GlassTokens.sub : GlassTokens.tert,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetSection() {
    final full = _presets.length >= PresetStore.maxPresets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassGroup(
          children: [
            for (final p in _presets) _presetTile(p),
            GlassPressable(
              onTap: full ? null : _savePreset,
              scale: 0.985,
              semanticLabel: '현재 구성 저장',
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: GlassTokens.tintText,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '현재 구성 저장',
                        style: GlassTokens.body.copyWith(
                          color: GlassTokens.tintText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_presets.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '자주 쓰는 운동 구성을 저장해 두면 여기서 바로 불러올 수 있어요.',
              style: GlassTokens.caption,
            ),
          ),
      ],
    );
  }

  Widget _presetTile(WorkoutPreset p) {
    final c = p.config;
    return GlassPressable(
      onTap: () => _applyPreset(p),
      onLongPress: () => _deletePreset(p),
      scale: 0.985,
      semanticLabel: p.name,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GlassTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '운동 ${fmtClock(c.workSeconds)} · 휴식 ${c.restSeconds == 0 ? '없음' : fmtClock(c.restSeconds)} · ${c.rounds}라운드'
                    '${c.sets > 1 ? ' · ${c.sets}세트' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GlassTokens.caption,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '삭제',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: GlassTokens.tert,
              ),
              onPressed: () => _deletePreset(p),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    Widget row(String k, String v, {bool strong = false}) => SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(k, style: GlassTokens.body.copyWith(color: GlassTokens.sub)),
            const Spacer(),
            Text(
              v,
              style: strong
                  ? GlassTokens.number(17).copyWith(fontWeight: FontWeight.w700)
                  : GlassTokens.body.copyWith(
                      fontFeatures: GlassTokens.tabular,
                    ),
            ),
          ],
        ),
      ),
    );
    return GlassGroup(
      children: [
        row('총 소요 시간', fmtKorean(_c.totalSeconds), strong: true),
        row('총 라운드', '${_c.totalRounds}회 (${_c.rounds}회 × ${_c.sets}세트)'),
        row('준비 시간', '${TabataConfig.prepareSeconds}초 (고정)'),
      ],
    );
  }
}

/// iOS 스타일 유리 스위치 — 트랙은 상태색, 손잡이는 흰 유리 구슬.
class _GlassSwitch extends StatelessWidget {
  const _GlassSwitch({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final bool value;
  final Color accent;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedOpacity(
          duration: GlassTokens.state,
          opacity: enabled ? 1 : 0.35,
          child: AnimatedContainer(
            duration: GlassTokens.state,
            curve: GlassTokens.stateCurve,
            width: 52,
            height: 32,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: value && enabled
                  ? accent
                  : GlassTokens.ink.withValues(alpha: 0.12),
              border: Border.all(
                color: Colors.white.withValues(alpha: value ? 0.5 : 0.8),
                width: 1,
              ),
            ),
            child: AnimatedAlign(
              duration: GlassTokens.state,
              curve: GlassTokens.pressOutCurve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Color(0xFFF1F2F6)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: GlassTokens.shadowInk.withValues(alpha: 0.22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
