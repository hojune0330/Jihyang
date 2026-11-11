import 'package:flutter/material.dart';

import 'glass_controls.dart';
import 'glass_surface.dart';
import 'glass_tokens.dart';

/// 투명 상단 바 + 유리 뒤로가기 버튼 (설정·기록 화면)
///
/// 배경이 비치도록 바 자체는 칠하지 않는다. 스크롤 시 내용이 바 밑으로
/// 지나가면 thick 유리 띠가 나타나 제목이 읽히게 한다.
class GlassNavBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassNavBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.scrolled = false,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// 내용이 바 아래로 스크롤되었는가 (true 면 유리 띠 표시)
  final bool scrolled;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: preferredSize.height + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: scrolled ? 1 : 0,
            duration: GlassTokens.state,
            child: const GlassSurface(
              material: GlassMaterial.thick,
              radius: 0,
              shadow: false,
              child: SizedBox.expand(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, top + 8, 12, 8),
            child: Row(
              children: [
                GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: '뒤로',
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GlassTokens.title,
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing ?? const SizedBox(width: 44),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 유리 바텀시트 (§6). 위쪽 xl 곡률, thick 재질, 손잡이.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: GlassTokens.shadowInk.withValues(alpha: 0.28),
    elevation: 0,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        0,
        8,
        8 + MediaQuery.viewInsetsOf(ctx).bottom,
      ),
      child: SafeArea(
        top: false,
        child: GlassSurface(
          material: GlassMaterial.thick,
          radius: GlassTokens.rXl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: GlassTokens.ink.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              builder(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 다이얼로그 버튼 정의
class GlassDialogAction<T> {
  const GlassDialogAction({
    required this.label,
    required this.value,
    this.destructive = false,
    this.primary = false,
  });

  final String label;
  final T value;
  final bool destructive;
  final bool primary;
}

/// 유리 다이얼로그 (§6). 버튼은 아래쪽에 가로로 나란히, 중요 동작은 굵게.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  required List<GlassDialogAction<T>> actions,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: GlassTokens.shadowInk.withValues(alpha: 0.30),
    transitionDuration: GlassTokens.state,
    pageBuilder: (ctx, _, _) => _GlassDialog<T>(
      title: title,
      message: message,
      content: content,
      actions: actions,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final a = CurvedAnimation(parent: anim, curve: GlassTokens.stateCurve);
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 1.06, end: 1.0).animate(a),
          child: child,
        ),
      );
    },
  );
}

class _GlassDialog<T> extends StatelessWidget {
  const _GlassDialog({
    required this.title,
    required this.message,
    required this.content,
    required this.actions,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<GlassDialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          36,
          24,
          36,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            type: MaterialType.transparency,
            child: GlassSurface(
              material: GlassMaterial.thick,
              radius: GlassTokens.rLg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GlassTokens.headline.copyWith(fontSize: 17),
                    ),
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 2, 22, 4),
                      child: Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: GlassTokens.caption.copyWith(
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (content != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                      child: content,
                    ),
                  const SizedBox(height: 16),
                  Container(
                    height: 0.6,
                    color: GlassTokens.ink.withValues(alpha: 0.12),
                  ),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0)
                            Container(
                              width: 0.6,
                              color: GlassTokens.ink.withValues(alpha: 0.12),
                            ),
                          Expanded(child: _actionButton(context, actions[i])),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(BuildContext context, GlassDialogAction<T> a) {
    return GlassPressable(
      onTap: () => Navigator.of(context).pop(a.value),
      semanticLabel: a.label,
      child: SizedBox(
        height: 52,
        child: Center(
          child: Text(
            a.label,
            style: TextStyle(
              color: a.destructive ? GlassTokens.workText : GlassTokens.ink,
              fontSize: 15.5,
              fontWeight: a.primary ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
