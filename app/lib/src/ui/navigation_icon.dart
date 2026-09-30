import 'package:flutter/material.dart';

/// 短促的選取回饋；停留在分頁時不持續播放，也尊重系統減少動畫設定。
class NavigationIcon extends StatelessWidget {
  const NavigationIcon({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
  });

  final IconData icon;
  final IconData selectedIcon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return AnimatedSlide(
      offset: selected ? const Offset(0, -0.08) : Offset.zero,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: selected ? 1.08 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: Icon(selected ? selectedIcon : icon),
      ),
    );
  }
}
