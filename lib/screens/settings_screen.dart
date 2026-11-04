import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../theme/app_theme.dart';
import '../widgets/duration_setter.dart';

/// 별도 화면 — 운동 설정
///
/// 필요한 항목만 배치한다: 운동 시간 / 휴식 시간 / 라운드 / 세트 / 세트 간 휴식 / 음성·효과음
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

  void _update(TabataConfig next) => setState(() => _c = next);

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
                  color: AppColors.work,
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            DurationSetter(
              label: '운동 시간',
              seconds: _c.workSeconds,
              accent: AppColors.work,
              onChanged: (v) => _update(_c.copyWith(workSeconds: v)),
            ),
            const SizedBox(height: 20),
            DurationSetter(
              label: '휴식 시간',
              seconds: _c.restSeconds,
              accent: AppColors.rest,
              allowZero: true,
              onChanged: (v) => _update(_c.copyWith(restSeconds: v)),
            ),
            const SizedBox(height: 26),
            _countRow(
              label: '라운드',
              value: _c.rounds,
              unit: '회',
              min: 1,
              max: 99,
              accent: AppColors.prepare,
              onChanged: (v) => _update(_c.copyWith(rounds: v)),
            ),
            const SizedBox(height: 14),
            _countRow(
              label: '세트',
              value: _c.sets,
              unit: '세트',
              min: 1,
              max: 20,
              accent: AppColors.textPrimary,
              onChanged: (v) => _update(_c.copyWith(sets: v)),
            ),
            if (_c.sets > 1) ...[
              const SizedBox(height: 20),
              DurationSetter(
                label: '세트 간 휴식',
                seconds: _c.setRestSeconds,
                accent: AppColors.rest,
                allowZero: true,
                onChanged: (v) => _update(_c.copyWith(setRestSeconds: v)),
              ),
            ],
            const SizedBox(height: 26),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 8),
            _switchRow(
              label: '음성 안내',
              subtitle: '운동·휴식 안내와 5초 카운트다운 음성',
              value: _c.voiceEnabled,
              accent: AppColors.prepare,
              onChanged: (v) => _update(_c.copyWith(voiceEnabled: v)),
            ),
            _switchRow(
              label: '효과음',
              subtitle: '시작·전환·완료 알림음',
              value: _c.sfxEnabled,
              accent: AppColors.work,
              onChanged: (v) => _update(_c.copyWith(sfxEnabled: v)),
            ),
            const SizedBox(height: 22),
            _summaryCard(),
          ],
        ),
      ),
    );
  }

  Widget _countRow({
    required String label,
    required int value,
    required String unit,
    required int min,
    required int max,
    required Color accent,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _stepBtn(
            Icons.remove_rounded,
            value > min ? () => onChanged(value - 1) : null,
            accent,
          ),
          SizedBox(
            width: 82,
            child: Center(
              child: Text(
                '$value$unit',
                style: TextStyle(
                  color: accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _stepBtn(
            Icons.add_rounded,
            value < max ? () => onChanged(value + 1) : null,
            accent,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap, Color color) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 62,
        child: Icon(
          icon,
          size: 22,
          color: enabled
              ? color
              : AppColors.textTertiary.withValues(alpha: 0.45),
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
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.black,
              activeTrackColor: accent,
              inactiveThumbColor: AppColors.textSecondary,
              inactiveTrackColor: AppColors.surfaceHigh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final m = _c.totalSeconds ~/ 60;
    final s = _c.totalSeconds % 60;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
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
                m >= 60
                    ? '${m ~/ 60}시간 ${m % 60}분'
                    : '$m분 ${s.toString().padLeft(2, '0')}초',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                  fontSize: 15,
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
