import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../services/audio_coach.dart';
import '../theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _c = widget.initial;
  }

  void _update(TabataConfig next) {
    setState(() => _c = next);
    // 설정 즉시 반영 (미리 듣기 볼륨/목소리)
    AudioCoach.instance.applyConfig(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '운동 설정',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(_c),
              child: const Text(
                '저장',
                style: TextStyle(
                  color: AppColors.prepare,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
          children: [
            const _SectionLabel('운동 구성'),
            const SizedBox(height: 6),
            _wheelRow(
              label: '운동 시간',
              value: fmtClock(_c.workSeconds),
              accent: AppColors.work,
              onTap: () => _openDuration(
                title: '운동 시간',
                subtitle: '한 라운드 동안 운동하는 시간입니다.',
                seconds: _c.workSeconds,
                accent: AppColors.work,
                minSeconds: 5,
                apply: (v) => _update(_c.copyWith(workSeconds: v)),
              ),
            ),
            const SizedBox(height: 10),
            _wheelRow(
              label: '휴식 시간',
              value: fmtClock(_c.restSeconds),
              accent: AppColors.rest,
              onTap: () => _openDuration(
                title: '휴식 시간',
                subtitle: '라운드 사이에 쉬는 시간입니다. 0초면 휴식 없이 진행합니다.',
                seconds: _c.restSeconds,
                accent: AppColors.rest,
                minSeconds: 0,
                apply: (v) => _update(_c.copyWith(restSeconds: v)),
              ),
            ),
            const SizedBox(height: 10),
            _wheelRow(
              label: '라운드',
              value: '${_c.rounds}회',
              accent: AppColors.prepare,
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
            const SizedBox(height: 10),
            _wheelRow(
              label: '세트',
              value: '${_c.sets}세트',
              accent: AppColors.textPrimary,
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
            const SizedBox(height: 10),
            if (_c.sets > 1)
              _wheelRow(
                label: '세트 간 휴식',
                value: fmtClock(_c.setRestSeconds),
                accent: AppColors.rest,
                onTap: () => _openDuration(
                  title: '세트 간 휴식',
                  subtitle: '세트가 바뀔 때 쉬는 시간입니다. 마지막 세트 뒤에는 적용되지 않습니다.',
                  seconds: _c.setRestSeconds,
                  accent: AppColors.rest,
                  minSeconds: 0,
                  apply: (v) => _update(_c.copyWith(setRestSeconds: v)),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  '세트가 1개면 세트 간 휴식은 사용되지 않습니다.',
                  style: TextStyle(
                    color: AppColors.textTertiary.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            _summaryCard(),

            const SizedBox(height: 26),
            const _SectionLabel('사운드'),
            const SizedBox(height: 4),
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
              enabled: _c.soundEnabled && _c.voiceEnabled,
              onChanged: (v) => _update(_c.copyWith(voiceVolume: v)),
              onPreview: () =>
                  AudioCoach.instance.previewVoice(_c.voiceStyle),
            ),
            const SizedBox(height: 6),
            _voiceStyleSection(),
            if (!_c.soundEnabled) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '전체 사운드가 꺼져 있어 음성·효과음 설정이 적용되지 않습니다.',
                      style: TextStyle(
                        color: AppColors.textTertiary.withValues(alpha: 0.95),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Center(
              child: Text(
                '준비 시간 ${TabataConfig.prepareSeconds}초는 항상 포함됩니다.',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
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
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
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
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
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
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.unfold_more_rounded,
              size: 19,
              color: AppColors.textTertiary,
            ),
          ],
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
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: dim
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: dim
                          ? AppColors.textTertiary.withValues(alpha: 0.6)
                          : AppColors.textTertiary,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: AppColors.ink,
              activeTrackColor: accent,
              inactiveThumbColor: AppColors.textSecondary,
              inactiveTrackColor: AppColors.surfaceHigh,
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
    required bool enabled,
    required ValueChanged<double> onChanged,
    required VoidCallback onPreview,
  }) {
    final dim = !enabled;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: dim ? AppColors.textTertiary : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  color: dim ? AppColors.textTertiary : accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 30,
                child: TextButton(
                  onPressed: dim ? null : onPreview,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '미리 듣기',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.2,
              activeTrackColor: dim
                  ? AppColors.textTertiary.withValues(alpha: 0.4)
                  : accent,
              inactiveTrackColor: AppColors.surfaceHigh,
              thumbColor: dim ? AppColors.textTertiary : accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '목소리 종류',
            style: TextStyle(
              color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '각 목소리를 눌러 미리 들어볼 수 있습니다.',
            style: TextStyle(
              color: AppColors.textTertiary.withValues(alpha: 0.95),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          for (final style in VoiceStyle.values) ...[
            _voiceTile(style, enabled),
            if (style != VoiceStyle.values.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _voiceTile(VoiceStyle style, bool enabled) {
    final selected = _c.voiceStyle == style;
    final accent = AppColors.prepare;
    return InkWell(
      onTap: enabled
          ? () {
              _update(_c.copyWith(voiceStyle: style));
              AudioCoach.instance.previewVoice(style);
            }
          : null,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.tinted(accent)
              : AppColors.surfaceHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.55)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: selected
                  ? accent
                  : AppColors.textTertiary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    style.label,
                    style: TextStyle(
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    style.description,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: enabled
                  ? () => AudioCoach.instance.previewVoice(style)
                  : null,
              iconSize: 20,
              tooltip: '미리 듣기',
              icon: Icon(
                Icons.volume_up_rounded,
                color: enabled ? accent : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '총 소요 시간',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                fmtKorean(_c.totalSeconds),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Text(
                '총 라운드',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${_c.totalRounds}회  (${_c.rounds}회 × ${_c.sets}세트)',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Text(
                '준비 시간',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${TabataConfig.prepareSeconds}초 (고정)',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
