import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import '../widgets/depth_button.dart';
import '../widgets/timer_display.dart';
import '../widgets/setting_stepper.dart';

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

  void _applyPreset(String name, TabataConfig preset) {
    setState(() {
      _c = preset.copyWith(
        soundEnabled: _c.soundEnabled,
        vibrationEnabled: _c.vibrationEnabled,
      );
    });
    SoundService.instance.vibrate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('타바타 설정'),
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: DepthButton(
            onTap: () => Navigator.of(context).pop(),
            icon: Icons.arrow_back_rounded,
            accent: AppColors.textPrimary,
            width: 42,
            height: 42,
            radius: 14,
            iconSize: 20,
          ),
        ),
        leadingWidth: 70,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: DepthButton(
              onTap: () {
                SoundService.instance.vibrate();
                Navigator.of(context).pop(_c);
              },
              label: '저장',
              accent: AppColors.work,
              filled: true,
              width: 74,
              height: 42,
              radius: 14,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 22),

            _sectionTitle('타바타 구성'),
            const SizedBox(height: 10),
            SettingStepper(
              title: '운동 개수',
              subtitle: '한 세트 안에서 수행할 운동 개수',
              value: _c.exerciseCount,
              unit: '개',
              suffix: '개',
              min: 1,
              max: 30,
              accent: AppColors.work,
              onChanged: (v) => _update(_c.copyWith(exerciseCount: v)),
            ),
            const SizedBox(height: 10),
            SettingStepper(
              title: '세트 수',
              subtitle: '전체 세트 반복 횟수',
              value: _c.setCount,
              unit: '세트',
              suffix: '세트',
              min: 1,
              max: 20,
              accent: AppColors.setRest,
              onChanged: (v) => _update(_c.copyWith(setCount: v)),
            ),
            const SizedBox(height: 10),
            SettingStepper(
              title: '세트 간 휴식',
              subtitle: '세트가 끝난 뒤 쉬는 시간',
              value: _c.setRestMinutes,
              unit: '분 휴식',
              suffix: '분 휴식',
              min: 0,
              max: 10,
              accent: AppColors.minutes,
              onChanged: (v) => _update(_c.copyWith(setRestMinutes: v)),
            ),

            const SizedBox(height: 22),
            _sectionTitle('시간 설정'),
            const SizedBox(height: 10),
            SettingStepper(
              title: '운동 시간',
              subtitle: '운동 1개당 시간',
              value: _c.workSeconds,
              unit: '초',
              suffix: '초',
              min: 5,
              max: 120,
              step: 5,
              accent: AppColors.seconds,
              onChanged: (v) => _update(_c.copyWith(workSeconds: v)),
            ),
            const SizedBox(height: 10),
            SettingStepper(
              title: '운동 사이 휴식',
              subtitle: '운동과 운동 사이 짧은 휴식',
              value: _c.restSeconds,
              unit: '초',
              suffix: '초',
              min: 0,
              max: 60,
              step: 5,
              accent: AppColors.rest,
              onChanged: (v) => _update(_c.copyWith(restSeconds: v)),
            ),
            const SizedBox(height: 10),
            SettingStepper(
              title: '준비 시간',
              subtitle: '시작 전 카운트다운',
              value: _c.prepareSeconds,
              unit: '초',
              suffix: '초',
              min: 0,
              max: 30,
              step: 5,
              accent: AppColors.prepare,
              onChanged: (v) => _update(_c.copyWith(prepareSeconds: v)),
            ),

            const SizedBox(height: 22),
            _sectionTitle('알림'),
            const SizedBox(height: 10),
            _buildToggle(
              title: '사운드 알림',
              subtitle: '운동·휴식 종료 5초 전부터 비프음',
              icon: Icons.volume_up_rounded,
              color: AppColors.work,
              value: _c.soundEnabled,
              onChanged: (v) => _update(_c.copyWith(soundEnabled: v)),
            ),
            const SizedBox(height: 10),
            _buildToggle(
              title: '진동 알림',
              subtitle: '구간 전환 및 카운트다운 진동',
              icon: Icons.vibration_rounded,
              color: AppColors.setRest,
              value: _c.vibrationEnabled,
              onChanged: (v) => _update(_c.copyWith(vibrationEnabled: v)),
            ),

            const SizedBox(height: 22),
            _sectionTitle('빠른 프리셋'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _presetChip(
                  '클래식 타바타',
                  const TabataConfig(
                    workSeconds: 20,
                    restSeconds: 10,
                    exerciseCount: 8,
                    setCount: 1,
                    setRestMinutes: 0,
                  ),
                ),
                _presetChip(
                  '3세트 인터벌',
                  const TabataConfig(
                    workSeconds: 20,
                    restSeconds: 10,
                    exerciseCount: 8,
                    setCount: 3,
                    setRestMinutes: 2,
                  ),
                ),
                _presetChip(
                  '지구력 40/20',
                  const TabataConfig(
                    workSeconds: 40,
                    restSeconds: 20,
                    exerciseCount: 6,
                    setCount: 2,
                    setRestMinutes: 3,
                  ),
                ),
                _presetChip(
                  '스프린트 15/15',
                  const TabataConfig(
                    workSeconds: 15,
                    restSeconds: 15,
                    exerciseCount: 10,
                    setCount: 2,
                    setRestMinutes: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            DepthButton(
              onTap: () {
                SoundService.instance.vibrate();
                Navigator.of(context).pop(_c);
              },
              label: '이 설정으로 시작',
              icon: Icons.play_arrow_rounded,
              accent: AppColors.work,
              filled: true,
              height: 58,
              expand: true,
              fontSize: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: AppColors.seconds,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
      ),
    ],
  );

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceHigh, AppColors.surface, Colors.black],
        ),
        border: Border.all(color: AppColors.stroke, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '총 소요 시간',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${_c.exerciseCount}개 · ${_c.setCount}세트 · ${_c.setRestMinutes}분 휴식',
                style: const TextStyle(
                  color: AppColors.minutes,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TimerDisplay(
              totalSeconds: _c.totalSeconds,
              fontSize: 46,
              dimZeroHours: false,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat('순수 운동', _c.pureWorkSeconds, AppColors.work),
              Container(width: 1, height: 26, color: AppColors.stroke),
              _miniStat(
                '총 운동 개수',
                _c.exerciseCount * _c.setCount,
                AppColors.setRest,
                isTime: false,
              ),
              Container(width: 1, height: 26, color: AppColors.stroke),
              _miniStat('세트 수', _c.setCount, AppColors.minutes, isTime: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int value, Color color, {bool isTime = true}) {
    final text = isTime ? _fmt(value) : '$value';
    return Expanded(
      child: Column(
        children: [
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () {
        SoundService.instance.vibrate();
        onChanged(!value);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: value ? 0.18 : 0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: color.withValues(alpha: value ? 0.4 : 0.14),
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: color.withValues(alpha: value ? 1 : 0.45),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: Colors.black,
              activeTrackColor: color,
              inactiveThumbColor: AppColors.textSecondary,
              inactiveTrackColor: AppColors.surfaceHigh,
              onChanged: (v) {
                SoundService.instance.vibrate();
                onChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, TabataConfig preset) {
    final selected =
        _c.workSeconds == preset.workSeconds &&
        _c.restSeconds == preset.restSeconds &&
        _c.exerciseCount == preset.exerciseCount &&
        _c.setCount == preset.setCount;
    return DepthButton(
      onTap: () => _applyPreset(label, preset),
      label: label,
      accent: selected ? AppColors.work : AppColors.textPrimary,
      filled: selected,
      height: 42,
      radius: 13,
      fontSize: 12.5,
    );
  }

  String _fmt(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
